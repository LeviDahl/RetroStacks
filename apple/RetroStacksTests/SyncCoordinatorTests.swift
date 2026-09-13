import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Regression coverage for `SyncCoordinator`'s pull/resolve/push pipeline — the
/// last-write-wins merge logic is genuinely easy to get backwards (which side
/// wins, which side gets re-pushed), and none of it touches the network, so a
/// fake `CollectionSyncEngine` is the right level per `CLAUDE.md`'s Testing
/// Discipline rather than waiting for a UI test against a live Supabase project.
@Suite(.serialized)
struct SyncCoordinatorTests {

    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-syncc-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "rs-syncc-tests-\(UUID().uuidString)")!
    }

    @MainActor
    private func insertLocalItem(exportID: UUID, updatedAt: Date, notes: String, into context: ModelContext) -> CollectionItem {
        let item = CollectionItem(status: .owned, notes: notes, exportID: exportID)
        item.updatedAt = updatedAt
        context.insert(item)
        return item
    }

    private func remoteChange(exportID: UUID, updatedAt: Date, notes: String, deletedAt: Date? = nil) -> CollectionChange {
        CollectionChange(
            exportID: exportID,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            payload: CollectionArchive.Entry(
                exportID: exportID, catalogSlug: nil, catalogName: nil, platformShortName: nil,
                status: "owned", condition: nil, completeness: nil,
                hasBox: false, hasManual: false, hasInserts: false, hasOriginalPackaging: false,
                gradingCompany: "none", gradeScore: nil, pricePaid: nil, dateAcquired: nil,
                acquisitionSource: nil, estimatedValueOverride: nil, storageLocation: nil,
                notes: notes, playStatus: nil, dateAdded: updatedAt, updatedAt: updatedAt, photosBase64: []
            )
        )
    }

    // MARK: - First sync

    @MainActor
    @Test func firstSyncInsertsRemoteItemsAndPushesUnsyncedLocalOnes() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let localID = UUID()
        _ = insertLocalItem(exportID: localID, updatedAt: .now, notes: "local only", into: context)
        try context.save()

        let remoteID = UUID()
        let engine = FakeCollectionSyncEngine()
        engine.pullResult = .success([remoteChange(exportID: remoteID, updatedAt: .now, notes: "from remote")])

        let coordinator = SyncCoordinator(engine: engine, isSignedIn: { true }, defaults: freshDefaults())
        await coordinator.sync(into: context)

        guard case .synced = coordinator.phase else {
            Issue.record("expected .synced, got \(coordinator.phase)")
            return
        }

        let items = try context.fetch(FetchDescriptor<CollectionItem>())
        #expect(items.count == 2, "the remote-only item should have been inserted locally")
        #expect(items.contains { $0.exportID == remoteID && $0.notes == "from remote" })

        // The never-before-synced local item should have gone out in the push,
        // and only that one — the just-inserted remote item shouldn't be echoed back.
        #expect(engine.pushedChanges.map(\.exportID) == [localID])
    }

    // MARK: - Conflict resolution

    @MainActor
    @Test func newerRemoteChangeOverwritesLocalAndIsNotPushedBack() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let id = UUID()
        let older = Date.now.addingTimeInterval(-3600)
        let newer = Date.now
        _ = insertLocalItem(exportID: id, updatedAt: older, notes: "stale local", into: context)
        try context.save()

        let engine = FakeCollectionSyncEngine()
        engine.pullResult = .success([remoteChange(exportID: id, updatedAt: newer, notes: "fresher remote")])

        let coordinator = SyncCoordinator(engine: engine, isSignedIn: { true }, defaults: freshDefaults())
        await coordinator.sync(into: context)

        let item = try #require(context.fetch(FetchDescriptor<CollectionItem>()).first { $0.exportID == id })
        #expect(item.notes == "fresher remote")
        #expect(engine.pushedChanges.isEmpty, "a change we just lost to remote shouldn't be echoed back in the same push")
    }

    @MainActor
    @Test func newerLocalChangeBeatsOlderRemoteAndGetsPushed() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let id = UUID()
        let older = Date.now.addingTimeInterval(-3600)
        let newer = Date.now
        _ = insertLocalItem(exportID: id, updatedAt: newer, notes: "fresh local", into: context)
        try context.save()

        let engine = FakeCollectionSyncEngine()
        engine.pullResult = .success([remoteChange(exportID: id, updatedAt: older, notes: "stale remote")])

        let coordinator = SyncCoordinator(engine: engine, isSignedIn: { true }, defaults: freshDefaults())
        await coordinator.sync(into: context)

        let item = try #require(context.fetch(FetchDescriptor<CollectionItem>()).first { $0.exportID == id })
        #expect(item.notes == "fresh local", "local should win — it's newer")
        #expect(engine.pushedChanges.map(\.exportID) == [id])
    }

    // MARK: - Failure surfacing

    @MainActor
    @Test func pullFailureReportsToStatusCenterAndLeavesLocalDataAlone() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let id = UUID()
        _ = insertLocalItem(exportID: id, updatedAt: .now, notes: "untouched", into: context)
        try context.save()

        let engine = FakeCollectionSyncEngine()
        engine.pullResult = .failure(SyncError.transport("offline"))

        let coordinator = SyncCoordinator(engine: engine, isSignedIn: { true }, defaults: freshDefaults())
        await coordinator.sync(into: context)

        guard case .failed = coordinator.phase else {
            Issue.record("expected .failed, got \(coordinator.phase)")
            return
        }
        let issue = try #require(AppStatusCenter.shared.issues.first { $0.source == .collectionSync })
        #expect(issue.severity == .warning)
        #expect(issue.retry != nil)

        let item = try #require(context.fetch(FetchDescriptor<CollectionItem>()).first { $0.exportID == id })
        #expect(item.notes == "untouched")
    }

    @MainActor
    @Test func signedOutIsANoOp() async throws {
        let context = try freshContext()
        let engine = FakeCollectionSyncEngine()
        engine.pullResult = .success([remoteChange(exportID: UUID(), updatedAt: .now, notes: "should never land")])

        let coordinator = SyncCoordinator(engine: engine, isSignedIn: { false }, defaults: freshDefaults())
        await coordinator.sync(into: context)

        #expect(coordinator.phase == .idle)
        #expect(try context.fetchCount(FetchDescriptor<CollectionItem>()) == 0)
    }
}

/// Test double for `CollectionSyncEngine` — captures what got pushed so a test
/// can assert on it, and lets pull fail on demand.
private final class FakeCollectionSyncEngine: CollectionSyncEngine, @unchecked Sendable {
    var isEnabled = true
    var pullResult: Result<[CollectionChange], Error> = .success([])
    private(set) var pushedChanges: [CollectionChange] = []

    func pull(since date: Date?) async throws -> [CollectionChange] { try pullResult.get() }

    func push(_ changes: [CollectionChange]) async throws -> [CollectionChange] {
        pushedChanges = changes
        return changes
    }
}
