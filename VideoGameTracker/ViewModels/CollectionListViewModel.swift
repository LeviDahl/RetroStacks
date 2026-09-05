import Foundation
import Observation

@MainActor
@Observable
final class CollectionListViewModel {
    enum SortField: String, CaseIterable, Identifiable {
        case recentlyAdded, title, platform, estimatedValue, pricePaid
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recentlyAdded: "Recently Added"
            case .title: "Title"
            case .platform: "Platform"
            case .estimatedValue: "Est. Value"
            case .pricePaid: "Price Paid"
            }
        }
    }

    var searchText = ""
    var statusFilter: CollectionStatus? = .owned
    var kindFilter: ItemKind?
    var platformSlugFilter: String?
    var sortField: SortField = .recentlyAdded
    var sortAscending = false

    /// Applies the current search / filter / sort to a fetched set.
    func apply(to items: [CollectionItem]) -> [CollectionItem] {
        var result = items

        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        if let kindFilter {
            result = result.filter { $0.kind == kindFilter }
        }
        if let platformSlugFilter {
            result = result.filter { $0.catalogItem?.platform?.slug == platformSlugFilter }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.title.lowercased().contains(query)
                    || item.platformShortName.lowercased().contains(query)
                    || item.notes.lowercased().contains(query)
            }
        }

        result.sort { lhs, rhs in
            let ascending = sortAscending
            switch sortField {
            case .recentlyAdded:
                return compare(lhs.dateAdded, rhs.dateAdded, ascending: ascending)
            case .title:
                return compare(lhs.title.lowercased(), rhs.title.lowercased(), ascending: ascending)
            case .platform:
                return compare(lhs.platformShortName, rhs.platformShortName, ascending: ascending)
            case .estimatedValue:
                return compare(lhs.estimatedValue ?? 0, rhs.estimatedValue ?? 0, ascending: ascending)
            case .pricePaid:
                return compare(lhs.pricePaid ?? 0, rhs.pricePaid ?? 0, ascending: ascending)
            }
        }
        return result
    }

    var hasActiveFilters: Bool {
        kindFilter != nil || platformSlugFilter != nil
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func clearFilters() {
        searchText = ""
        kindFilter = nil
        platformSlugFilter = nil
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T, ascending: Bool) -> Bool {
        ascending ? lhs < rhs : lhs > rhs
    }
}
