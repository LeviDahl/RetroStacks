import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Regression coverage for `CatalogSyncService.sync(into:)` — the full
/// fetch → decode → reconcile → SwiftData pipeline, using a fake
/// `CatalogRepository` instead of the network. No live server involved.
///
/// `validSyncInsertsItemsWithMissingOptionalFields` exists specifically because
/// this shipped broken: `FeedItem.summary` was non-optional while ~3,500 of the
/// real feed's items never carry that field (see `ingest/libretro.mjs`), so
/// every sync silently failed from the first such item onward. That bug lived
/// entirely below the UI, so a fast unit test — not a UI test — is what should
/// have caught it. Shaping the fake feed after the real one (summary absent,
/// several other optionals absent too) is the point: this is what actually
/// ships, not a tidy hand-picked fixture.
@Suite(.serialized)
struct CatalogSyncServiceTests {

    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-sync-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    /// Mirrors the real feed shape as closely as practical: one curated-style
    /// item (everything filled in) and one import-style item (only what
    /// ingest/libretro.mjs actually emits — no summary, no developer/genre/upc).
    private static func feedShapedLikeReality() -> CatalogFeed {
        let platform = FeedPlatform(
            slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
            manufacturer: "Nintendo", generation: 4, releaseYearNA: 1991, discontinuedYearNA: 1999,
            summary: "16-bit Nintendo.", iconSystemName: "gamecontroller", regions: ["NA"]
        )
        let curated = FeedItem(
            slug: "snes-chrono-trigger", platformSlug: "snes", kind: "game", name: "Chrono Trigger",
            variant: nil, releaseYearNA: 1995, manufacturerOrPublisher: "Square",
            developer: "Square", genre: "RPG", upc: nil,
            summary: "Dream-team JRPG.",
            imageURL: "https://example.com/ct.png", imageCredit: "Box art", imageLicense: "Publisher artwork"
        )
        let imported = FeedItem(
            slug: "snes-imported-title", platformSlug: "snes", kind: "game", name: "Some Imported Game",
            variant: nil, releaseYearNA: 1993, manufacturerOrPublisher: "Konami",
            developer: nil, genre: nil, upc: nil,
            summary: nil,
            imageURL: "https://example.com/box.png", imageCredit: "Box art via Libretro thumbnails",
            imageLicense: "Publisher artwork"
        )
        return CatalogFeed(version: "1", generatedAt: .now, platforms: [platform], items: [curated, imported])
    }

    // MARK: - Success

    @MainActor
    @Test func validSyncInsertsItemsWithMissingOptionalFields() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let repo = FakeCatalogRepository(result: .success(Self.feedShapedLikeReality()))
        let service = CatalogSyncService(repository: repo)

        await service.sync(into: context)

        guard case .synced = service.phase else {
            Issue.record("expected .synced, got \(service.phase)")
            return
        }

        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        #expect(items.count == 2)

        let imported = try #require(items.first { $0.slug == "snes-imported-title" })
        #expect(imported.summary == "", "a missing feed summary should map to \"\", never crash the decode")
        #expect(imported.developer == nil)
        #expect(imported.genre == nil)
        #expect(imported.platform?.slug == "snes")

        let curated = try #require(items.first { $0.slug == "snes-chrono-trigger" })
        #expect(curated.summary == "Dream-team JRPG.")
        #expect(curated.developer == "Square")

        // A successful sync clears any earlier failure badge.
        #expect(!AppStatusCenter.shared.issues.contains { $0.source == .catalogSync })
    }

    // MARK: - Pruning (added 2026-09-18, alongside the admin-exclude feature)

    /// The common case: a public item vanished from the feed (e.g. an admin
    /// exclude) and nobody's collection references it — safe to actually
    /// delete, so every raw count (`platform.catalogItems.count`) is
    /// correct without any view needing to know about `isHidden` at all.
    @MainActor
    @Test func syncDeletesAnUnownedPublicItemMissingFromTheFeed() async throws {
        let context = try freshContext()
        let platform = Platform(
            slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
            manufacturer: "Nintendo", generation: 4
        )
        context.insert(platform)
        let stale = CatalogItem(slug: "snes-some-bootleg", kind: .game, name: "Some Bootleg")
        stale.platform = platform
        context.insert(stale)

        let service = CatalogSyncService(repository: FakeCatalogRepository(result: .success(Self.feedShapedLikeReality())))
        await service.sync(into: context)

        let remaining = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.slug == "snes-some-bootleg" }))
        #expect(remaining.isEmpty, "an unowned, missing-from-the-feed public item should be deleted outright")
    }

    /// The safety case: the same missing item, but someone owns it — must
    /// not be hard-deleted, since `CatalogItem`'s relationship to
    /// `CollectionItem` is `deleteRule: .cascade` and would silently take
    /// their real collection record with it. Falls back to `isHidden` —
    /// same effect everywhere that's already respected, none of the risk.
    @MainActor
    @Test func syncHidesRatherThanDeletesAnOwnedPublicItemMissingFromTheFeed() async throws {
        let context = try freshContext()
        let platform = Platform(
            slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
            manufacturer: "Nintendo", generation: 4
        )
        context.insert(platform)
        let stale = CatalogItem(slug: "snes-some-bootleg", kind: .game, name: "Some Bootleg")
        stale.platform = platform
        context.insert(stale)
        let entry = CollectionItem(catalogItem: stale, status: .owned)
        context.insert(entry)

        let service = CatalogSyncService(repository: FakeCatalogRepository(result: .success(Self.feedShapedLikeReality())))
        await service.sync(into: context)

        let survivors = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.slug == "snes-some-bootleg" }))
        let survivor = try #require(survivors.first, "an owned item must survive pruning, not be deleted")
        #expect(survivor.isHidden == true)
        let entries = try context.fetch(FetchDescriptor<CollectionItem>())
        #expect(entries.count == 1, "the real CollectionItem must not be cascade-deleted as a side effect")
    }

    /// Found live 2026-09-18: a tombstoned (soft-removed via `CollectionActions
    /// .remove`, which only sets `deletedAt`) `CollectionItem` still counts
    /// as "owned" under the raw `collectionEntries` relationship, so the
    /// first version of this pruning check wrongly hid instead of deleted
    /// every item that had ever been added-then-undone — exactly what
    /// happened when a user accidentally bulk-added ~560 review-candidate
    /// items, then used bulk-remove to undo it, then excluded them: all 560
    /// got hidden, none deleted, because the tombstoned entries were still
    /// attached. Must check `liveEntries` (deletedAt == nil only).
    @MainActor
    @Test func syncDeletesAPublicItemWhoseOnlyCollectionEntryIsSoftDeleted() async throws {
        let context = try freshContext()
        let platform = Platform(
            slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
            manufacturer: "Nintendo", generation: 4
        )
        context.insert(platform)
        let stale = CatalogItem(slug: "snes-some-bootleg", kind: .game, name: "Some Bootleg")
        stale.platform = platform
        context.insert(stale)
        let tombstoned = CollectionItem(catalogItem: stale, status: .owned)
        tombstoned.markDeleted()
        context.insert(tombstoned)

        let service = CatalogSyncService(repository: FakeCatalogRepository(result: .success(Self.feedShapedLikeReality())))
        await service.sync(into: context)

        let remaining = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.slug == "snes-some-bootleg" }))
        #expect(remaining.isEmpty, "a tombstoned collection entry must not count as \"owned\" — the item should still be deleted")
    }

    /// A private (user-created) item missing from this fetch usually just
    /// means the viewer is signed out or it's a different account's row —
    /// never treated as "the server deleted it," unlike a public item.
    @MainActor
    @Test func syncNeverPrunesAPrivateItemMissingFromTheFeed() async throws {
        let context = try freshContext()
        let platform = Platform(
            slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
            manufacturer: "Nintendo", generation: 4
        )
        context.insert(platform)
        let mine = CatalogItem(slug: "snes-my-custom-entry", kind: .game, name: "My Custom Entry")
        mine.platform = platform
        mine.ownerUserID = UUID()
        context.insert(mine)

        let service = CatalogSyncService(repository: FakeCatalogRepository(result: .success(Self.feedShapedLikeReality())))
        await service.sync(into: context)

        let survivors = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.slug == "snes-my-custom-entry" }))
        let survivor = try #require(survivors.first, "a private item must never be pruned just for being absent from a public-scoped fetch")
        #expect(survivor.isHidden == false)
    }

    /// A previously-excluded (or previously-hidden-by-pruning) item that
    /// reappears in a later feed should un-hide itself — mirrors
    /// `upsert_public_catalog_items` clearing `deleted_at` server-side on a
    /// re-conflict, so a mistaken exclude that gets reversed (`admin
    /// _restore_catalog_items`) actually shows up again on the next sync.
    @MainActor
    @Test func syncUnhidesAnItemThatReappearsInTheFeed() async throws {
        let context = try freshContext()
        let platform = Platform(
            slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
            manufacturer: "Nintendo", generation: 4
        )
        context.insert(platform)
        let previouslyExcluded = CatalogItem(slug: "snes-chrono-trigger", kind: .game, name: "Chrono Trigger")
        previouslyExcluded.platform = platform
        previouslyExcluded.isHidden = true
        context.insert(previouslyExcluded)

        let service = CatalogSyncService(repository: FakeCatalogRepository(result: .success(Self.feedShapedLikeReality())))
        await service.sync(into: context)

        let items = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.slug == "snes-chrono-trigger" }))
        let item = try #require(items.first)
        #expect(item.isHidden == false, "an item present in a fresh feed should never stay stuck hidden from an earlier prune")
    }

    // MARK: - Failure surfacing

    @MainActor
    @Test func decodingFailureReportsToStatusCenterAndKeepsExistingData() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let repo = FakeCatalogRepository(result: .failure(CatalogError.decoding("keyNotFound(\"summary\")")))
        let service = CatalogSyncService(repository: repo)

        await service.sync(into: context)

        guard case .failed = service.phase else {
            Issue.record("expected .failed, got \(service.phase)")
            return
        }
        let issue = try #require(AppStatusCenter.shared.issues.first { $0.source == .catalogSync })
        #expect(issue.severity == .warning)
        #expect(issue.retry != nil)

        // Nothing should have been written to the store on a failed decode.
        #expect(try context.fetchCount(FetchDescriptor<CatalogItem>()) == 0)
    }

    @MainActor
    @Test func retryAfterFailureClearsTheIssueOnSuccess() async throws {
        AppStatusCenter.shared.dismissAll()
        let context = try freshContext()
        let repo = FakeCatalogRepository(result: .failure(CatalogError.transport("offline")))
        let service = CatalogSyncService(repository: repo)

        await service.sync(into: context)
        #expect(AppStatusCenter.shared.issues.contains { $0.source == .catalogSync })

        repo.result = .success(Self.feedShapedLikeReality())
        await service.sync(into: context, forceReload: true)

        guard case .synced = service.phase else {
            Issue.record("expected .synced after retry, got \(service.phase)")
            return
        }
        #expect(!AppStatusCenter.shared.issues.contains { $0.source == .catalogSync })
    }
}

/// Test double for `CatalogRepository` — no network, no `URLSession`. `result`
/// is a class-backed `var` (not a struct copy) so a test can flip it between
/// calls, e.g. to simulate a failed sync followed by a successful retry.
private final class FakeCatalogRepository: CatalogRepository, @unchecked Sendable {
    var result: Result<CatalogFeed, Error>

    init(result: Result<CatalogFeed, Error>) {
        self.result = result
    }

    func fetchCatalog(forceReload: Bool) async throws -> CatalogFeed {
        try result.get()
    }

    func fetchPriceGuides(forceReload: Bool) async throws -> PriceGuideFeed {
        PriceGuideFeed(version: "1", generatedAt: .now, guides: [:])
    }
}
