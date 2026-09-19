import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// `CatalogPlatformRow` used to compute these per row on the main thread
/// (~1.3s per Catalog visit, live `sample` 2026-09-19). Locks down the one-pass
/// result matches what the row used to show: visible count + a console image.
struct PlatformOverviewTests {
    @MainActor
    @Test func countsVisibleItemsAndPicksAConsoleImage() throws {
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let nes = Platform(slug: "nes", name: "NES", shortName: "NES", manufacturer: "Nintendo", generation: 3)
        context.insert(nes)
        let game = CatalogItem(slug: "nes-game", kind: .game, name: "Game")
        let hidden = CatalogItem(slug: "nes-hidden", kind: .game, name: "Hidden")
        hidden.isHidden = true
        let bare = CatalogItem(slug: "nes-console-a", kind: .console, name: "A")
        let pictured = CatalogItem(slug: "nes-console-b", kind: .console, name: "B")
        pictured.imageURLString = "https://example.com/nes.png"
        for item in [game, hidden, bare, pictured] {
            item.platform = nes
            context.insert(item)
        }
        let all = try context.fetch(FetchDescriptor<CatalogItem>())

        let visible = PlatformOverview.compute(from: all, includeHidden: false)["nes"]
        #expect(visible?.entryCount == 3)
        #expect(visible?.heroImageURL == URL(string: "https://example.com/nes.png"))
        #expect(PlatformOverview.compute(from: all, includeHidden: true)["nes"]?.entryCount == 4)
    }
}
