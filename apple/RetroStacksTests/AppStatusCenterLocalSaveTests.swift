import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Regression coverage for `ModelContext.saveLoggingErrors(reportingAs:)`
/// (`AppLog.swift`) and the `.localSave` `AppStatusCenter.Source` it can
/// report through — added 2026-09-15 alongside that helper, prepping for a
/// real-usage session where a silent save failure would otherwise leave
/// someone unsure whether an add/edit actually stuck.
///
/// Only the success path is exercised here. Two real attempts at forcing an
/// actual `ModelContext.save()` throw were tried and both taught something,
/// but neither produced a reliable, safe-to-run failure:
/// 1. A duplicate `CatalogItem.slug` (`@Attribute(.unique)`), expecting a
///    constraint-violation throw — SwiftData silently merges/upserts on a
///    unique-key collision here instead of throwing.
/// 2. Dropping the store directory's write permission after an initial
///    successful save — POSIX permission checks happen at `open()` time, not
///    per `write()`; SwiftData's connection was already open from the first
///    save, so a later chmod has no effect on it. A *new* container opened
///    fresh against a read-only path would fail, but that failure happens in
///    `ModelContainer.init`, not `ModelContext.save()` — a different
///    function than the one this file means to cover.
/// A third option — corrupting the live SQLite file's bytes to force a real
/// I/O error mid-save — was ruled out as unsafe to attempt in an automated
/// test: SwiftData/CoreData hitting unrecoverable store corruption can
/// `fatalError` rather than throw a catchable `Error`, which would crash the
/// test process instead of exercising the `catch` branch.
/// `saveLoggingErrors`'s failure branch is a plain 4-line `catch` (log, and
/// if a `source` was given, report + return `false`) — correctness there is
/// evident on inspection, and the wiring above it (which call sites pass
/// `.localSave` vs. stay logging-only) is a compile-time-checked parameter,
/// not runtime logic worth a forced-failure test to protect.
@Suite(.serialized)
struct AppStatusCenterLocalSaveTests {

    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-localsave-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    private static func catalogItem(slug: String) -> CatalogItem {
        CatalogItem(slug: slug, kind: .game, name: "Test Game")
    }

    @MainActor
    @Test func successfulSaveClearsAnyExistingLocalSaveIssue() throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        AppStatusCenter.shared.report(.localSave, severity: .error, title: "stale issue from a prior failure")

        context.insert(Self.catalogItem(slug: "n64-ok"))
        let succeeded = context.saveLoggingErrors(reportingAs: .localSave)

        #expect(succeeded)
        #expect(!AppStatusCenter.shared.issues.contains { $0.source == .localSave })
    }

    @MainActor
    @Test func nilSourceNeverTouchesStatusCenterOnSuccess() throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()

        context.insert(Self.catalogItem(slug: "n64-background"))
        let succeeded = context.saveLoggingErrors() // no source — background-write style

        #expect(succeeded)
        // A background write (CatalogSeedStore/CatalogSyncService/PricingService
        // style, no `reportingAs:`) must never populate `.localSave` — that
        // source is reserved for user-initiated collection edits.
        #expect(!AppStatusCenter.shared.issues.contains { $0.source == .localSave })
    }
}
