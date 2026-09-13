#!/bin/bash
# Runs SwiftLint over the apple/ target using the repo-root .swiftlint.yml.
# Needs `brew install swiftlint` once; nothing else to set up (deliberately
# not an Xcode Build Phase or SPM plugin — both would mean editing
# project.pbxproj/package deps, off-limits per CLAUDE.md).
#
# Usage:
#   Scripts/lint.sh          # report only
#   Scripts/lint.sh --fix    # auto-fix what SwiftLint can fix safely, then report what's left

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "swiftlint not found — install with: brew install swiftlint"
    exit 1
fi

if [[ "${1:-}" == "--fix" ]]; then
    swiftlint --fix
    echo
    echo "== re-checking after --fix =="
fi

swiftlint lint
