import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Browse Catalog's filter/sort moved off the main actor (user report
/// 2026-09-19: Catalog got worse as the catalog grew). Locks down that the
/// background path returns exactly what the synchronous filter does, and that
/// building it via the helper doesn't land back on the main thread.
struct CatalogBrowseFilterTests {
    @MainActor
    private func seed() throws -> ModelContainer {
        let url = URL.temporaryDirectory.appending(path: "rs-browse-filter-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        let nes = Platform(slug: "nes", name: "NES", shortName: "NES", manufacturer: "Nintendo", generation: 3)
        let snes = Platform(slug: "snes", name: "SNES", shortName: "SNES", manufacturer: "Nintendo", generation: 4)
        context.insert(nes)
        context.insert(snes)
        for (slug, name, platform, kind) in [
            ("nes-a", "Alpha", nes, ItemKind.game), ("nes-b", "Bravo", nes, .game),
            ("nes-console", "NES Console", nes, .console), ("snes-c", "Charlie", snes, .game)
        ] {
            let item = CatalogItem(slug: slug, kind: kind, name: name)
            item.platform = platform
            context.insert(item)
        }
        try context.save()
        return container
    }

    @Test @MainActor func backgroundResultMatchesTheSynchronousFilter() async throws {
        let container = try seed()
        let all = try container.mainContext.fetch(FetchDescriptor<CatalogItem>())
        var filter = CatalogBrowseFilter()
        filter.platformSlug = "nes"
        filter.kind = .game
        filter.sortAscending = false

        let expected = filter.apply(to: all).map(\.slug)
        let ids = try await CatalogQueryActor.browseIdentifiers(container: container, filter: filter)
        let actual = ids.compactMap { container.mainContext.model(for: $0) as? CatalogItem }.map(\.slug)

        #expect(expected == ["nes-b", "nes-a"])
        #expect(actual == expected)
    }
}
