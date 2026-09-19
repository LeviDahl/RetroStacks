import Foundation
import SwiftData
import os

// Split out of SystemGamesList.swift 2026-09-17 (type_body_length, pushed
// from a warning into a hard error by the reviewCandidatesOnly heuristic
// below): the pure catalog-computation logic — filtering, sorting, and the
// review-candidate heuristic — none of which touches `self`, so this needed
// no access-level changes beyond what testability (see
// `SystemGamesListReviewCandidateTests`) already required. Same reasoning as
// the `SystemGamesListRows.swift` split.

/// The filter/sort settings `SystemGamesList` keeps as separate `@State`/
/// `@AppStorage` properties, bundled for everything downstream of it —
/// added 2026-09-18 when `loadCatalog` (the background-actor fix) pushed
/// the individual-parameter version of these functions to 9 params,
/// tripping `function_parameter_count`'s error threshold. Also just a
/// better shape: every function below wants the exact same bundle, and this
/// is the one place that spells out its fields, instead of the same 7-8
/// names repeated at every call site.
nonisolated struct CatalogFilterOptions: Sendable {
    var kindFilter: SystemGamesList.KindFilter
    var searchText: String
    var sortField: SystemGamesList.SortField
    var sortAscending: Bool
    var showHidden: Bool
    var reviewCandidatesOnly: Bool
    var showNonNARegions: Bool
}

extension SystemGamesList {
    /// A real publisher published many games on a platform; a ROM hacker's
    /// own handle (IGDB's community-contributed `involved_companies` can't
    /// structurally tell the two apart — confirmed live, see
    /// `reviewCandidatesOnly`'s doc comment) published exactly one or two.
    /// Applies across the platform's *whole* catalog, not just whatever else
    /// is currently filtered — the point is "how many games has this
    /// publisher name published here, period."
    nonisolated static let rarePublisherThreshold = 3

    /// Not `private` — same reasoning as `SupabaseCatalogItemRow`: this is
    /// the one piece of `reviewCandidatesOnly` that's pure logic (everything
    /// else is SwiftUI/SwiftData plumbing), and it's only actually exercised
    /// by constructing real fixtures and checking real outputs, not by
    /// reading the code.
    nonisolated static func isReviewCandidate(_ item: CatalogItem, publisherCounts: [String: Int]) -> Bool {
        let lastPlausibleYear = item.platform?.discontinuedYearNA ?? item.platform?.releaseYearNA ?? Int.max
        // A release year past the platform's plausible lifetime is
        // sufficient on its own — no legitimate NA release happens decades
        // after a platform's discontinuation, regardless of publisher. A
        // publisher-frequency veto here previously hid every item from a
        // prolific homebrew author (e.g. an N64 ROM-hacker with 18 titles
        // under one handle) even when the year was unambiguous.
        if let year = item.releaseYearNA {
            return year > lastPlausibleYear
        }

        let publisher = item.manufacturerOrPublisher?.trimmingCharacters(in: .whitespaces)
        return publisher.map { (publisherCounts[$0] ?? 0) <= rarePublisherThreshold } ?? true
    }

    nonisolated static func computeCatalog(platform: Platform, options: CatalogFilterOptions) -> [CatalogItem] {
        let q = options.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var publisherCounts: [String: Int] = [:]
        if options.reviewCandidatesOnly {
            for item in platform.catalogItems {
                guard let pub = item.manufacturerOrPublisher?.trimmingCharacters(in: .whitespaces), !pub.isEmpty else { continue }
                publisherCounts[pub, default: 0] += 1
            }
        }
        let filtered = platform.catalogItems.filter { item in
            (options.showHidden || !item.isHidden)
                && (options.showNonNARegions || (item.regions?.contains(.northAmerica) ?? true))
                && (options.kindFilter.kind == nil || item.kind == options.kindFilter.kind)
                && (q.isEmpty
                    || item.name.lowercased().contains(q)
                    || (item.variant?.lowercased().contains(q) ?? false)
                    || (item.manufacturerOrPublisher?.lowercased().contains(q) ?? false))
                && (!options.reviewCandidatesOnly || isReviewCandidate(item, publisherCounts: publisherCounts))
        }
        return filtered.sorted { a, b in
            switch options.sortField {
            case .title:
                return ascendingCompare(a.name.lowercased(), b.name.lowercased(), sortAscending: options.sortAscending)
            case .releaseYear:
                return ascendingCompare(a.releaseYearNA ?? .max, b.releaseYearNA ?? .max,
                                         sortAscending: options.sortAscending, tiebreak: (a.name, b.name))
            case .publisher:
                return ascendingCompare(a.manufacturerOrPublisher ?? "~", b.manufacturerOrPublisher ?? "~",
                                         sortAscending: options.sortAscending, tiebreak: (a.name, b.name))
            case .value:
                let av = a.ownedEntry?.estimatedValue ?? a.headlineValue ?? 0
                let bv = b.ownedEntry?.estimatedValue ?? b.headlineValue ?? 0
                return ascendingCompare(av, bv, sortAscending: options.sortAscending, tiebreak: (a.name, b.name))
            }
        }
    }

    /// One comparator every sort field routes through, `sortAscending`-aware.
    /// Equal primary values fall back to `tiebreak` (always name-ascending, so
    /// ties never look shuffled) when one is supplied.
    nonisolated static func ascendingCompare<T: Comparable>(
        _ lhs: T, _ rhs: T, sortAscending: Bool, tiebreak: (String, String)? = nil
    ) -> Bool {
        if lhs != rhs { return sortAscending ? lhs < rhs : lhs > rhs }
        guard let tiebreak else { return false }
        return tiebreak.0.localizedCaseInsensitiveCompare(tiebreak.1) == .orderedAscending
    }

    nonisolated static func indexLetter(for title: String) -> String {
        guard let first = title.uppercased().unicodeScalars.first else { return "#" }
        return CharacterSet.uppercaseLetters.contains(first) ? String(first) : "#"
    }

    static func catalogCacheKey(platform: Platform, options: CatalogFilterOptions) -> String {
        "\(platform.slug)|\(options.kindFilter.rawValue)|\(options.searchText)|\(options.sortField.rawValue)|"
            + "\(options.sortAscending)|\(options.showHidden)|\(options.reviewCandidatesOnly)|\(options.showNonNARegions)"
    }

    /// Off the main actor via `CatalogQueryActor` — makes the relationship-
    /// fault+sort cost disappear from the main thread instead of just being
    /// deferred past the nav animation. Falls back to the synchronous path
    /// only if the background fetch throws (shouldn't happen — same store).
    /// Takes everything as parameters rather than reading `self` — same
    /// reason `computeCatalog` above does: stays callable from here, in a
    /// different file than `SystemGamesList`'s own `private` state.
    static func loadCatalog(
        platform: Platform, options: CatalogFilterOptions, modelContext: ModelContext
    ) async -> [CatalogItem] {
        do {
            let ids = try await CatalogQueryActor.identifiers(
                container: modelContext.container, platformSlug: platform.slug, options: options
            )
            return ids.compactMap { modelContext.model(for: $0) as? CatalogItem }
        } catch {
            AppLog.sync.error(
                "CatalogQueryActor.catalogItemIdentifiers failed, falling back: \(String(describing: error), privacy: .public)"
            )
            return computeCatalog(platform: platform, options: options)
        }
    }
}
