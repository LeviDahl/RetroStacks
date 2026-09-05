import Foundation
import Observation

@MainActor
@Observable
final class CatalogBrowseViewModel {
    enum SortField: String, CaseIterable, Identifiable {
        case title, releaseYear, value
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title: "Title"
            case .releaseYear: "Release Year"
            case .value: "Reference Value"
            }
        }
    }

    var searchText = ""
    var kindFilter: ItemKind?
    var platformSlugFilter: String?
    var generationFilter: Int?
    var sortField: SortField = .title
    var sortAscending = true
    var ownershipFilter: OwnershipFilter = .all

    enum OwnershipFilter: String, CaseIterable, Identifiable {
        case all, owned, notOwned, wishlist
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .owned: "Owned"
            case .notOwned: "Not Owned"
            case .wishlist: "Wishlist"
            }
        }
    }

    func apply(to items: [CatalogItem]) -> [CatalogItem] {
        var result = items

        if let kindFilter { result = result.filter { $0.kind == kindFilter } }
        if let platformSlugFilter { result = result.filter { $0.platform?.slug == platformSlugFilter } }
        if let generationFilter { result = result.filter { $0.platform?.generation == generationFilter } }

        switch ownershipFilter {
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

    var hasActiveFilters: Bool {
        kindFilter != nil || platformSlugFilter != nil || generationFilter != nil
            || ownershipFilter != .all
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func clearFilters() {
        searchText = ""
        kindFilter = nil
        platformSlugFilter = nil
        generationFilter = nil
        ownershipFilter = .all
    }

    private func cmp<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
        sortAscending ? lhs < rhs : lhs > rhs
    }
}
