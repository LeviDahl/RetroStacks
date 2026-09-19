import Foundation

/// The Browse Catalog filter/sort as a plain `Sendable` value, so it can run
/// off the main actor in `CatalogQueryActor` — `CatalogSection` used to run
/// this over the whole ~16k-item `@Query` result on the main thread every
/// time the screen appeared (`onAppear`) or a filter changed. Live `sample`
/// of the app 2026-09-19 + user report: Catalog got noticeably worse as the
/// catalog grew. `CatalogBrowseViewModel.apply(to:)` now just delegates here.
nonisolated struct CatalogBrowseFilter: Sendable {
    var kind: ItemKind?
    var platformSlug: String?
    var generation: Int?
    var ownership: CatalogBrowseViewModel.OwnershipFilter = .all
    var searchText = ""
    var sortField: CatalogBrowseViewModel.SortField = .title
    var sortAscending = true
    var showHidden = false
    var showNonNARegions = false

    func apply(to items: [CatalogItem]) -> [CatalogItem] {
        var result = items

        if !showHidden { result = result.filter { !$0.isHidden } }
        if !showNonNARegions {
            result = result.filter { $0.regions?.contains(.northAmerica) ?? true }
        }
        if let kind { result = result.filter { $0.kind == kind } }
        if let platformSlug { result = result.filter { $0.platform?.slug == platformSlug } }
        if let generation { result = result.filter { $0.platform?.generation == generation } }

        switch ownership {
        case .all: break
        case .owned: result = result.filter(\.isOwned)
        case .notOwned: result = result.filter { !$0.isOwned }
        case .wishlist: result = result.filter(\.isWishlisted)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.name.lowercased().contains(query)
                    || (item.variant?.lowercased().contains(query) ?? false)
                    || (item.manufacturerOrPublisher?.lowercased().contains(query) ?? false)
                    || (item.developer?.lowercased().contains(query) ?? false)
                    || item.platformShortName.lowercased().contains(query)
            }
        }

        result.sort { lhs, rhs in
            switch sortField {
            case .title:
                return cmp(lhs.name.lowercased(), rhs.name.lowercased())
            case .releaseYear:
                return cmp(lhs.releaseYearNA ?? 0, rhs.releaseYearNA ?? 0)
            case .value:
                return cmp(lhs.headlineValue ?? 0, rhs.headlineValue ?? 0)
            }
        }
        return result
    }

    private func cmp<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
        sortAscending ? lhs < rhs : lhs > rhs
    }
}
