import Foundation
import SwiftData

/// Runs `SystemGamesList.computeCatalog`'s relationship-fault-heavy filter
/// and sort off the main actor. Previously this ran on `@MainActor` even
/// though it was already deferred via `.task(id:)` (past the navigation
/// push animation, not off the main thread) — the same real cost, first
/// measured at 1.4-3.4s against the on-disk dev store (see FEATURES.md's
/// sidebar-lag entry), was still blocking the UI whenever it actually ran.
///
/// A `@ModelActor` gets its own `ModelContext` on the same store, so
/// `computeCatalog` can run completely unchanged here — it never touches
/// `self` or anything MainActor-isolated, just the `Platform`/`CatalogItem`
/// parameters it's given, and those now come from *this* actor's own fetch
/// instead of the live cross-actor relationship. Only `PersistentIdentifier`s
/// (Sendable) cross back to the caller; the caller resolves them to live
/// `@Model` references on its own context.
@ModelActor
actor CatalogQueryActor {
    func catalogItemIdentifiers(
        platformSlug: String, options: CatalogFilterOptions
    ) throws -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<Platform>(predicate: #Predicate { $0.slug == platformSlug })
        guard let platform = try modelContext.fetch(descriptor).first else { return [] }

        let items = SystemGamesList.computeCatalog(platform: platform, options: options)
        return items.map(\.persistentModelID)
    }

    func browseIdentifiers(filter: CatalogBrowseFilter) throws -> [PersistentIdentifier] {
        let items = try modelContext.fetch(FetchDescriptor<CatalogItem>())
        return filter.apply(to: items).map(\.persistentModelID)
    }
}

extension CatalogQueryActor {
    /// See `CollectionSummariesActor.summaries` — building a `@ModelActor`
    /// from the main actor pins it to the main thread; `@concurrent` doesn't.
    @concurrent
    static func identifiers(
        container: ModelContainer, platformSlug: String, options: CatalogFilterOptions
    ) async throws -> [PersistentIdentifier] {
        let actor = CatalogQueryActor(modelContainer: container)
        return try await actor.catalogItemIdentifiers(platformSlug: platformSlug, options: options)
    }
}

extension CatalogQueryActor {
    @concurrent
    static func browseIdentifiers(
        container: ModelContainer, filter: CatalogBrowseFilter
    ) async throws -> [PersistentIdentifier] {
        try await CatalogQueryActor(modelContainer: container).browseIdentifiers(filter: filter)
    }
}
