import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// `SystemGamesList.isReviewCandidate` — the heuristic for bootlegs/ROM
/// hacks/homebrew that slipped into the IGDB import. Verified 2026-09-17
/// against real IGDB data before being built (see `BACKLOG.md`'s Phase 5
/// section) — these fixtures lock down the exact decision boundary that
/// real check established, not a re-guess of it.
///
/// A release year past the platform's plausible lifetime is sufficient on
/// its own, regardless of publisher — fixed 2026-09-18 after a live example
/// (an N64 item, publisher "MorningStorm64", 2022) escaped detection
/// because that publisher had crossed the rare-publisher count threshold
/// with *other* homebrew releases, and the old logic required *both*
/// signals together, letting a hard publisher-frequency veto suppress an
/// otherwise-unambiguous late year. Publisher rarity now only matters as a
/// fallback when the year is missing entirely.
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

    /// A missing year alone isn't enough — a common, well-established
    /// publisher shouldn't get flagged just because one row has no release
    /// year on file at all.
    @Test @MainActor func commonPublisherWithAMissingYearIsNotACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let missingYear = item(context, platform: platform, name: "Nintendo No Year", year: nil, publisher: "Nintendo")
        let counts = ["Nintendo": 90]

        #expect(SystemGamesList.isReviewCandidate(missingYear, publisherCounts: counts) == false)
    }

    /// The fix this file's header documents, locked down directly: a common
    /// publisher does NOT protect a late release year — this is exactly the
    /// shape of the real N64 item that escaped detection under the old
    /// logic (a prolific homebrew alias crossing the rare-publisher count
    /// threshold with unambiguously post-discontinuation release years).
    @Test @MainActor func commonPublisherWithALateYearIsStillACandidate() throws {
        let context = try freshContext()
        let platform = nes(in: context)
        let lateReissue = item(context, platform: platform, name: "Nintendo Reissue", year: 2010, publisher: "Nintendo")
        let counts = ["Nintendo": 90]

        #expect(SystemGamesList.isReviewCandidate(lateReissue, publisherCounts: counts) == true)
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
