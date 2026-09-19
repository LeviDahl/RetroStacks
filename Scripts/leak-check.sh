#!/bin/bash
# Exhaustive, unattended Leaks check for the macOS build of RetroStacks.
# See FEATURES.md's "Automated leak testing — exhaustive, unattended" for the
# full story of how each piece here was figured out; this script is Phase 1 +
# Phase 3 of that plan (Phase 2, the walkthrough itself, is
# RetroStacksUITests/AppWalkthroughTests.swift).
#
# What it does, in order:
#   1. Builds RetroStacks with real project signing (NOT CODE_SIGNING_ALLOWED=NO
#      — that strips the com.apple.security.get-task-allow entitlement xctrace
#      needs to attach at all).
#   2. Launches it with -uiTesting (deterministic in-memory seed, no real
#      network sync racing the walkthrough).
#   3. Attaches `xctrace record --instrument Leaks` to that running process —
#      the bare Leaks instrument, not --template Leaks, which bundles the
#      Allocations instrument's full backtrace logging and reliably crashed
#      xctrace's own save step on this machine (NSArchiver's ~4GB ceiling) even
#      over a ~90s recording.
#   4. Runs AppWalkthroughTests against that same already-running instance
#      (XCUIApplication(bundleIdentifier:), no .launch()) to actually drive it.
#   5. Stops the recording with SIGINT (not SIGKILL — xctrace needs to flush
#      and save the trace cleanly).
#   6. Exports the Leaks detail table headlessly and greps it for <row>
#      elements. Empty = no leaks; exits non-zero with the leaked objects
#      printed if any are found.
#
# Usage: Scripts/leak-check.sh
# Exit code: 0 = no leaks found, 1 = leaks found or the pipeline itself failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE_DIR="$REPO_ROOT/apple"
RESULTS_DIR="$REPO_ROOT/leak-results/$(date +%Y%m%d-%H%M%S)"
BUNDLE_ID="com.levidahlstrom.RetroStacks"
SCHEME="RetroStacks"
DESTINATION="platform=macOS"

mkdir -p "$RESULTS_DIR"
TRACE_PATH="$RESULTS_DIR/leaks.trace"
BUILD_LOG="$RESULTS_DIR/build.log"
TEST_LOG="$RESULTS_DIR/walkthrough.log"
RECORD_LOG="$RESULTS_DIR/xctrace-record.log"
RESULT_XML="$RESULTS_DIR/leaks-result.xml"

XCTRACE_PID=""
APP_PID=""

cleanup() {
    if [[ -n "$XCTRACE_PID" ]] && kill -0 "$XCTRACE_PID" 2>/dev/null; then
        kill -INT "$XCTRACE_PID" 2>/dev/null
        wait "$XCTRACE_PID" 2>/dev/null
    fi
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

echo "== leak-check: results going to $RESULTS_DIR"

echo "== leak-check: building (real signing — no CODE_SIGNING_ALLOWED=NO)"
if ! xcodebuild -project "$APPLE_DIR/RetroStacks.xcodeproj" -scheme "$SCHEME" \
    -destination "$DESTINATION" build > "$BUILD_LOG" 2>&1; then
    echo "== leak-check: BUILD FAILED — see $BUILD_LOG"
    tail -40 "$BUILD_LOG"
    exit 1
fi

APP_PATH=$(xcodebuild -project "$APPLE_DIR/RetroStacks.xcodeproj" -scheme "$SCHEME" \
    -destination "$DESTINATION" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP_PATH="$APP_PATH/RetroStacks.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "== leak-check: couldn't find built app at $APP_PATH"
    exit 1
fi

if ! codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "get-task-allow"; then
    echo "== leak-check: built app is missing com.apple.security.get-task-allow —"
    echo "   xctrace won't be able to attach. Check for CODE_SIGNING_ALLOWED=NO"
    echo "   anywhere in this build path."
    exit 1
fi

echo "== leak-check: killing any already-running instance"
pkill -x RetroStacks 2>/dev/null
sleep 1

echo "== leak-check: launching (-uiTesting)"
open "$APP_PATH" --args -uiTesting
for _ in $(seq 1 20); do
    APP_PID=$(pgrep -x RetroStacks | head -1)
    [[ -n "$APP_PID" ]] && break
    sleep 0.5
done
if [[ -z "$APP_PID" ]]; then
    echo "== leak-check: app never appeared in the process list"
    exit 1
fi
echo "== leak-check: app running as PID $APP_PID"
sleep 2   # let launch-time allocation churn settle before recording starts

echo "== leak-check: attaching xctrace (Leaks instrument only, not --template Leaks)"
xcrun xctrace record --instrument 'Leaks' --attach "$APP_PID" --no-prompt \
    --output "$TRACE_PATH" > "$RECORD_LOG" 2>&1 &
XCTRACE_PID=$!
sleep 3   # give the recorder a moment to actually attach before the walkthrough starts

echo "== leak-check: running the walkthrough against the running instance"
xcodebuild test -project "$APPLE_DIR/RetroStacks.xcodeproj" -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:RetroStacksUITests/AppWalkthroughTests \
    > "$TEST_LOG" 2>&1
TEST_EXIT=$?
if [[ $TEST_EXIT -ne 0 ]]; then
    echo "== leak-check: walkthrough test failed (exit $TEST_EXIT) — see $TEST_LOG"
    echo "   Continuing to export whatever the recording captured before the failure."
fi

echo "== leak-check: stopping the recording"
kill -INT "$XCTRACE_PID" 2>/dev/null
wait "$XCTRACE_PID" 2>/dev/null
XCTRACE_PID=""

if [[ ! -e "$TRACE_PATH" ]]; then
    echo "== leak-check: no trace file was produced — see $RECORD_LOG"
    exit 1
fi

echo "== leak-check: exporting the Leaks detail table"
if ! xcrun xctrace export --input "$TRACE_PATH" \
    --xpath '/trace-toc/run[@number="1"]/data/track[@name="Leaks"]/detail[@name="Leaks"]' \
    --output "$RESULT_XML" 2>>"$RECORD_LOG"; then
    echo "== leak-check: xctrace export failed — see $RECORD_LOG"
    exit 1
fi

LEAK_COUNT=$(grep -c '<row>' "$RESULT_XML" 2>/dev/null || echo 0)

echo
echo "== leak-check: results in $RESULTS_DIR"
if [[ "$LEAK_COUNT" -eq 0 ]]; then
    echo "== leak-check: PASS — no leaks found."
    [[ $TEST_EXIT -ne 0 ]] && echo "   (but the walkthrough itself failed — check $TEST_LOG; coverage was incomplete)"
    exit 0
else
    echo "== leak-check: FAIL — $LEAK_COUNT leaked object(s) found:"
    echo
    cat "$RESULT_XML"
    exit 1
fi
