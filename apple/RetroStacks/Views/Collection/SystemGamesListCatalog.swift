import Foundation

// Split out of SystemGamesList.swift 2026-09-17 (type_body_length, pushed
// from a warning into a hard error by the reviewCandidatesOnly heuristic
// below): the pure catalog-computation logic — filtering, sorting, and the
// review-candidate heuristic — none of which touches `self`, so this needed
// no access-level changes beyond what testability (see
// `SystemGamesListReviewCandidateTests`) already required. Same reasoning as
// the `SystemGamesListRows.swift` split.

extension SystemGamesList {
    /// A real publisher published many games on a platform; a ROM hacker's
    /// own handle (IGDB's community-contributed `involved_companies` can't
    /// structurally tell the two apart — confirmed live, see
    /// `reviewCandidatesOnly`'s doc comment) published exactly one or two.
    /// Applies across the platform's *whole* catalog, not just whatever else
    /// is currently filtered — the point is "how many games has this
    /// publisher name published here, period."
    static let rarePublisherThreshold = 3

    /// Not `private` — same reasoning as `SupabaseCatalogItemRow`: this is
    /// the one piece of `reviewCandidatesOnly` that's pure logic (everything
    /// else is SwiftUI/SwiftData plumbing), and it's only actually exercised
    /// by constructing real fixtures and checking real outputs, not by
    /// reading the code.
    static func isReviewCandidate(_ item: CatalogItem, publisherCounts: [String: Int]) -> Bool {
        let publisher = item.manufacturerOrPublisher?.trimmingCharacters(in: .whitespaces)
        let publisherIsRare = publisher.map { (publisherCounts[$0] ?? 0) <= rarePublisherThreshold } ?? true
        guard publisherIsRare else { return false }

        guard let year = item.releaseYearNA else { return true }
        let lastPlausibleYear = item.platform?.discontinuedYearNA ?? item.platform?.releaseYearNA ?? Int.max
        return year > lastPlausibleYear
    }

    static func computeCatalog(
        platform: Platform, kindFilter: KindFilter, searchText: String,
        sortField: SortField, sortAscending: Bool, showHidden: Bool, reviewCandidatesOnly: Bool
    ) -> [CatalogItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var publisherCounts: [String: Int] = [:]
        if reviewCandidatesOnly {
            for item in platform.catalogItems {
                guard let pub = item.manufacturerOrPublisher?.trimmingCharacters(in: .whitespaces), !pub.isEmpty else { continue }
                publisherCounts[pub, default: 0] += 1
            }
        }
        let filtered = platform.catalogItems.filter { item in
            (showHidden || !item.isHidden)
                && (kindFilter.kind == nil || item.kind == kindFilter.kind)
                && (q.isEmpty
                    || item.name.lowercased().contains(q)
                    || (item.variant?.lowercased().contains(q) ?? false)
                    || (item.manufacturerOrPublisher?.lowercased().contains(q) ?? false))
                && (!reviewCandidatesOnly || isReviewCandidate(item, publisherCounts: publisherCounts))
        }
        return filtered.sorted { a, b in
            switch sortField {
            case .title:
                return ascendingCompare(a.name.lowercased(), b.name.lowercased(), sortAscending: sortAscending)
            case .releaseYear:
                return ascendingCompare(a.releaseYearNA ?? .max, b.releaseYearNA ?? .max,
                                         sortAscending: sortAscending, tiebreak: (a.name, b.name))
            case .publisher:
                return ascendingCompare(a.manufacturerOrPublisher ?? "~", b.manufacturerOrPublisher ?? "~",
                                         sortAscending: sortAscending, tiebreak: (a.name, b.name))
            case .value:
                let av = a.ownedEntry?.estimatedValue ?? a.headlineValue ?? 0
                let bv = b.ownedEntry?.estimatedValue ?? b.headlineValue ?? 0
                return ascendingCompare(av, bv, sortAscending: sortAscending, tiebreak: (a.name, b.name))
            }
        }
    }

    /// One comparator every sort field routes through, `sortAscending`-aware.
    /// Equal primary values fall back to `tiebreak` (always name-ascending, so
    /// ties never look shuffled) when one is supplied.
    static func ascendingCompare<T: Comparable>(
        _ lhs: T, _ rhs: T, sortAscending: Bool, tiebreak: (String, String)? = nil
    ) -> Bool {
        if lhs != rhs { return sortAscending ? lhs < rhs : lhs > rhs }
        guard let tiebreak else { return false }
        return tiebreak.0.localizedCaseInsensitiveCompare(tiebreak.1) == .orderedAscending
    }

    static func indexLetter(for title: String) -> String {
        guard let first = title.uppercased().unicodeScalars.first else { return "#" }
        return CharacterSet.uppercaseLetters.contains(first) ? String(first) : "#"
    }
}
