import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Locks down that `CatalogQueryActor` (a background `@ModelActor`) produces
/// the exact same result as the original synchronous
/// `SystemGamesList.computeCatalog` for the same inputs — the whole point of
/// moving this off the main actor (see FEATURES.md's sidebar-lag entry) was
/// to make it non-blocking without changing what it returns.
struct CatalogQueryActorTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let url = URL.temporaryDirectory.appending(path: "rs-catalog-query-actor-tests-\(UUID().uuidString).store")
        return try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    @MainActor
    private func seed(_ container: ModelContainer) throws -> Platform {
        let context = container.mainContext
        let platform = Platform(
            slug: "nes", name: "Nintendo Entertainment System", shortName: "NES",
            manufacturer: "Nintendo", generation: 3,
            releaseYearNA: 1985, discontinuedYearNA: 1995
        )
        context.insert(platform)

        let names = ["Zelda", "Metroid", "Kid Icarus", "Excitebike", "Punch-Out!!"]
        for (i, name) in names.enumerated() {
            let item = CatalogItem(
                slug: name.lowercased(), kind: .game, name: name,
                releaseYearNA: 1985 + i
            )
            item.manufacturerOrPublisher = "Nintendo"
            item.platform = platform
            context.insert(item)
        }
        try context.save()
        return platform
    }

    @Test @MainActor func backgroundActorMatchesSynchronousComputeForTheSameInputs() async throws {
        let container = try makeContainer()
        let platform = try seed(container)

        let options = CatalogFilterOptions(
            kindFilter: .games, searchText: "", sortField: .title, sortAscending: true,
            showHidden: false, reviewCandidatesOnly: false, showNonNARegions: true
        )
        let expected = SystemGamesList.computeCatalog(platform: platform, options: options).map(\.slug)

        let actor = CatalogQueryActor(modelContainer: container)
        let ids = try await actor.catalogItemIdentifiers(platformSlug: platform.slug, options: options)
        let actual = ids.compactMap { container.mainContext.model(for: $0) as? CatalogItem }.map(\.slug)

        #expect(actual == expected)
        #expect(actual == ["excitebike", "kid icarus", "metroid", "punch-out!!", "zelda"])
    }

    @Test @MainActor func backgroundActorRespectsSearchAndSortJustLikeTheSynchronousPath() async throws {
        let container = try makeContainer()
        let platform = try seed(container)

        let actor = CatalogQueryActor(modelContainer: container)
        // "Nintendo" (every item's publisher) doesn't contain "k", so this
        // only matches on name — unlike "i", which every item also matches
        // via the shared publisher field.
        let options = CatalogFilterOptions(
            kindFilter: .games, searchText: "k", sortField: .releaseYear, sortAscending: false,
            showHidden: false, reviewCandidatesOnly: false, showNonNARegions: true
        )
        let ids = try await actor.catalogItemIdentifiers(platformSlug: platform.slug, options: options)
        let names = ids.compactMap { container.mainContext.model(for: $0) as? CatalogItem }.map(\.name)

        // "k": Zelda(1985, no), Metroid(1986, no), Kid Icarus(1987, yes),
        // Excitebike(1988, yes), Punch-Out!!(1989, no). Newest-first.
        #expect(names == ["Excitebike", "Kid Icarus"])
    }

    @Test @MainActor func unknownPlatformSlugReturnsEmptyRatherThanThrowing() async throws {
        let container = try makeContainer()
        _ = try seed(container)

        let actor = CatalogQueryActor(modelContainer: container)
        let options = CatalogFilterOptions(
            kindFilter: .all, searchText: "", sortField: .title, sortAscending: true,
            showHidden: false, reviewCandidatesOnly: false, showNonNARegions: true
        )
        let ids = try await actor.catalogItemIdentifiers(platformSlug: "does-not-exist", options: options)
        #expect(ids.isEmpty)
    }
}
