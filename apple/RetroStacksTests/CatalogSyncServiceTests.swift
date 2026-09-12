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
