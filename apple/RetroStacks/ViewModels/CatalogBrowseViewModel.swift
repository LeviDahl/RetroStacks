import Foundation
import Observation

@MainActor
@Observable
final class CatalogBrowseViewModel {
    nonisolated enum SortField: String, CaseIterable, Identifiable {
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
    /// Off by default, same meaning as `SystemGamesList`'s own toggle
    /// (`CatalogItem.isHidden` — a personal hide, or an admin's catalog-wide
    /// exclude, represented locally the same way). Found live 2026-09-18:
    /// `apply(to:)` never checked `isHidden` at all, so Browse Catalog kept
    /// showing every excluded item with no way to filter them out, unlike
    /// the per-system drill-down. Plain stored property, not `@AppStorage`
    /// backed — deliberately independent of `SystemGamesList`'s toggle,
    /// matching every other filter on this view model, which also resets
    /// each time Browse Catalog is opened fresh.
    var showHidden = false

    /// Off by default — matches the old ingest behavior of only carrying
    /// confirmed-NA (or unconfirmed) items, now done here instead of at
    /// ingest time. `CatalogItem.regions == nil` (no region data at all)
    /// always counts as NA regardless of this toggle, same "assume NA"
    /// posture as everywhere else this field is read. See BACKLOG.md's
    /// "EU / JP region switch."
    var showNonNARegions = false

    nonisolated enum OwnershipFilter: String, CaseIterable, Identifiable {
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

    var filter: CatalogBrowseFilter {
        CatalogBrowseFilter(
            kind: kindFilter, platformSlug: platformSlugFilter, generation: generationFilter,
            ownership: ownershipFilter, searchText: searchText, sortField: sortField,
            sortAscending: sortAscending, showHidden: showHidden, showNonNARegions: showNonNARegions
        )
    }

    func apply(to items: [CatalogItem]) -> [CatalogItem] { filter.apply(to: items) }

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

}
