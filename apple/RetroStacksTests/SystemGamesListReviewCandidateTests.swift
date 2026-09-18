import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// `SystemGamesList.isReviewCandidate` — the two-signal (rare/missing
/// publisher AND out-of-window/missing release year) heuristic for
/// bootlegs/ROM hacks/homebrew that slipped into the IGDB import, requiring
/// *both* signals deliberately so a real-but-obscure publisher or a hack
/// that happens to credit a real company doesn't get flagged. Verified
/// 2026-09-17 against real IGDB data before being built (see `BACKLOG.md`'s
/// Phase 5 section) — these fixtures lock down the exact decision boundary
/// that real check established, not a re-guess of it.
struct SystemGamesListReviewCandidateTests {
    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-review-candidate-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    @MainActor
    private func nes(in context: ModelContext) -> Platform {
        let platform = Platform(
            slug: "nes", name: "Nintendo Entertainment System", shortName: "NES",
            manufacturer: "Nintendo", generation: 3,
            releaseYearNA: 1985, discontinuedYearNA: 1995
        )
        context.insert(platform)
        return platform
    }

    @MainActor
    private func item(
        _ context: ModelContext, platform: Platform, name: String,
        year: Int?, publisher: String?
    ) -> CatalogItem {
        let item = CatalogItem(slug: name.lowercased(), kind: .game, name: name, releaseYearNA: year)
        item.manufacturerOrPublisher = publisher
        item.platform = platform
        context.insert(item)
        return item
    }

    @Test @MainActor func realGameWithCommonPublisherAndPeriodYearIsNotACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let real = item(context, platform: platform, name: "Super Mario Bros. 3", year: 1990, publisher: "Nintendo")
        let counts = ["Nintendo": 90]

        #expect(SystemGamesList.isReviewCandidate(real, publisherCounts: counts) == false)
    }

    @Test @MainActor func hackWithRarePublisherAndLateYearIsACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let hack = item(context, platform: platform, name: "Super Mario Bros. 3 Alpha", year: 2023, publisher: "sukoritai")
        let counts = ["Nintendo": 90, "sukoritai": 1]

        #expect(SystemGamesList.isReviewCandidate(hack, publisherCounts: counts) == true)
    }

    @Test @MainActor func missingPublisherAndMissingYearIsACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let hack = item(context, platform: platform, name: "Super Mario Bros. Ultra Deluxe", year: nil, publisher: nil)

        #expect(SystemGamesList.isReviewCandidate(hack, publisherCounts: [:]) == true)
    }

    /// Rare publisher alone isn't enough — a real, obscure period-accurate
    /// release must not get flagged just for being from a small publisher.
    @Test @MainActor func rarePublisherWithAPeriodAccurateYearIsNotACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let obscureButReal = item(
            context, platform: platform, name: "Some Obscure Real NES Game",
            year: 1991, publisher: "Tiny Real Publisher"
        )
        let counts = ["Tiny Real Publisher": 1]

        #expect(SystemGamesList.isReviewCandidate(obscureButReal, publisherCounts: counts) == false)
    }

    /// A late/missing year alone isn't enough — a common, well-established
    /// publisher shouldn't get flagged just because one row is missing a
    /// year or has a late one (e.g. a reissue).
    @Test @MainActor func commonPublisherWithALateOrMissingYearIsNotACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let lateReissue = item(context, platform: platform, name: "Nintendo Reissue", year: 2010, publisher: "Nintendo")
        let missingYear = item(context, platform: platform, name: "Nintendo No Year", year: nil, publisher: "Nintendo")
        let counts = ["Nintendo": 90]

        #expect(SystemGamesList.isReviewCandidate(lateReissue, publisherCounts: counts) == false)
        #expect(SystemGamesList.isReviewCandidate(missingYear, publisherCounts: counts) == false)
    }

    @Test @MainActor func publisherAtExactlyTheRareThresholdCounts() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let atThreshold = item(
            context, platform: platform, name: "At Threshold", year: 2020,
            publisher: "Borderline Publisher"
        )
        let counts = ["Borderline Publisher": SystemGamesList.rarePublisherThreshold]

        #expect(SystemGamesList.isReviewCandidate(atThreshold, publisherCounts: counts) == true)
    }
}
