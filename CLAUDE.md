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
Utilize the following `XcodeBuildMCP` compatible tools. Do not guess `xcodebuild` flags.
- **Build App**: `xcodebuild -scheme YourAppScheme -destination 'platform=iOS Simulator,name=iPhone 16' build`
- **Run Tests**: `xcodebuild -scheme YourAppScheme -destination 'platform=iOS Simulator,name=iPhone 16' test`
- **Lint Code**: `swift package plugin swiftlint` (or project-specific SwiftLint script)

## 📋 Code Conventions & Style Guide
- **File Layout**: Every new view file MUST include a standard `#Preview` block at the bottom.
- **Swift 6 Concurrency**: Enforce `@MainActor` isolated UI types and explicit structured concurrency (`async/await`). Avoid `DispatchQueue.main.async`.
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
- `AccessibilityAuditTests` runs `performAccessibilityAudit()` every UI-test
  pass but doesn't fail on findings yet (the app has ~zero accessibility
  coverage — see the Accessibility section of `BACKLOG.md`). Tighten it as
  that backlog item lands; don't just delete it.

## 🗂️ Backlog
Enhancement ideas and deferred work live in [`BACKLOG.md`](BACKLOG.md). Add to it
rather than letting good ideas evaporate mid-task; near-term implementation TODOs
stay in the `api/` and `apple/` READMEs.
