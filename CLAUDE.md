# CLAUDE.md — iOS Project Guide

## 🎯 Project Context & Architecture
- **Tech Stack**: iOS 26.0+ / Swift 6.0+ / Xcode 26.2+
- **UI Framework**: 100% SwiftUI matching Apple's modern "Liquid Glass" design language.
- **State & Data**: SwiftData for persistence, `@Observable` for domain state, and native local `LanguageModel` protocols for on-device AI routing.
- **Architecture**: Strict MVVM or Clean Architecture. No massive views. Keep data-flow unidirectional.

## 🛑 CRITICAL GUARDRAILS (Strict Enforcement)
1. **NEVER modify `.pbxproj` or `.xcodeproj` files directly**.
   - Creating or rewriting `.swift` files is allowed.
   - Rely strictly on Xcode's File System Synchronization. 
   - If manual target assignment is required, prompt the human user.
2. **Do NOT write any network layer code if on-device alternatives exist**. Prioritize Apple's native Foundation Models framework.
3. **No old SwiftUI modifiers**: Keep UI code compatible with the latest SDKs (e.g., do not call `.background()` modifiers before a `.glassEffect()` hierarchy).

## 🛠️ Build, Test, & Simulator Commands
- **Build App**: `xcodebuild -project apple/RetroStacks.xcodeproj -scheme RetroStacks -destination 'platform=iOS Simulator,name=iPhone 17' build`
- **Run Tests**: `xcodebuild -project apple/RetroStacks.xcodeproj -scheme RetroStacks -destination 'platform=iOS Simulator,name=iPhone 17' test`
- macOS-hosted UI tests (`-destination 'platform=macOS'`) need a real, unlocked
  interactive login session to inject synthetic events — they hang
  indefinitely in a headless/automated session. The iOS Simulator destination
  has no such requirement and is reliable headless; prefer it for
  `RetroStacksUITests` unless macOS-specific behavior is actually in question.
- **Lint Code**: `Scripts/lint.sh` (add `--fix` to auto-fix what's safe first). Config is
  `.swiftlint.yml` at the repo root. Deliberately not an Xcode Build Phase or SPM
  plugin — both would mean editing `project.pbxproj`/package deps, off-limits per
  the guardrail above. Needs `brew install swiftlint` once.

## 📋 Code Conventions & Style Guide
- **File Layout**: Every new view file MUST include a standard `#Preview` block at the bottom.
- **Swift 6 Concurrency**: Enforce `@MainActor` isolated UI types and explicit structured concurrency (`async/await`). Avoid `DispatchQueue.main.async`.
  - The project builds with `-default-isolation=MainActor`: a View's `.task` runs on the main actor, and anything meant to run off it (pure helpers, `Sendable` value types, `NSCache` keys) needs an explicit `nonisolated`.
  - A `@ModelActor` created from a `@MainActor` context runs its methods **on the main thread** (measured live, 2026-09-19). Build it inside a `@concurrent` static helper — see `CollectionSummariesActor.summaries` — and return only `Sendable` values / `PersistentIdentifier`s.
  - Don't run two `xcodebuild`s against the same simulator at once; it produces flaky failures.
- **Modularity**: Place functional code inside scoped directories (e.g., `/Models`, `/Views`, `/ViewModels`, `/Services`). Do not create generic "Utils" folders.
- **Previews**: Use mock container states or specialized preview data traits instead of live production environments.

## 🚀 Common Workflows for Claude
- **Plan Mode**: Run `claude` and initialize in plan mode (`/init` or explicit instructions) before attempting complex state logic changes.
- **Error Remediation**: If a compilation error breaks the pipeline, check for missing target imports or Swift concurrency isolation issues first.

## 🧪 Testing Discipline
- **When a bug reaches the user, it doesn't get closed out without a regression
  test.** Add the test *while fixing the bug*, not as a follow-up. Reason
  about why it wasn't already caught, and fix that gap too if it's cheap.
- **Pick the cheapest test that actually exercises the failure**, in this order:
  1. Pure unit test (`RetroStacksTests`, Swift Testing) — logic, decoding, model
     behavior. Fast, no UI, no simulator.
  2. Integration test with a fake dependency (e.g. a fake `CatalogRepository`
     driving `CatalogSyncService` end-to-end) — for bugs at a seam between
     components, still no UI needed.
  3. UI test (`RetroStacksUITests`, XCUITest) — **only** for what's literally
     impossible to test lower: rendering, navigation composition (this is how
     the `NavigationSplitView`/`NavigationStack` detail-column bug should have
     been caught), visual layout, accessibility.
- Launch UI tests with `-uiTesting` (`RetroStacksApp.isUITesting`) for a fresh
  in-memory store seeded from `SampleData` — deterministic, no real network
  sync, nothing left over between runs.
- `*AccessibilityAuditTests` (`RetroStacksUITests/NavigationTests.swift`) run
  `performAccessibilityAudit()` and **do** fail — as a ratchet against a
  `knownFindingBaseline` per screen, not a zero-tolerance gate (the app isn't
  fully clean yet). Lower a screen's baseline when you fix a real finding on
  it; see the Accessibility section of `BACKLOG.md` for current counts and
  what's already been investigated vs. still open.

## 🏷️ Versioning
Semantic versioning, `MAJOR.MINOR.PATCH`, pre-1.0 for now. `0.MINOR.0` = a coherent
feature set; `0.MINOR.PATCH` = fixes only. 1.0.0 is a deliberate milestone, not a
number that arrives on its own.
- Cut a version when a feature set is done, tests pass, and it's pushed — not per
  commit. Tag annotated on `main`: `git tag -a v0.6.0 -m "0.6.0 — <summary>"`, then push
  the tag (ask first; pushing is outward-facing).
- Add a row to the **Version history** table at the top of `FEATURES.md` in the same
  change. `MARKETING_VERSION` lives in the Xcode project — the user sets it (never edit
  `.pbxproj`); remind them to bump it to match the tag.

## 🗂️ Backlog
Enhancement ideas and deferred work live in [`BACKLOG.md`](BACKLOG.md) (open items
only); finished work and its history live in [`FEATURES.md`](FEATURES.md) — move an
entry there when it ships. Add to the backlog
rather than letting good ideas evaporate mid-task; near-term implementation TODOs
stay in the `api/` and `apple/` READMEs.
