import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Locks down the "one source of truth" fix (2026-09-18): excluding items
/// from the shared catalog (or personally hiding one) needs to disappear
/// from *every* count and browsing list, not just the one screen that
/// happened to filter `isHidden` already. Found live: excluding ~500 NES
/// bootlegs moved the per-system drill-down and (once `AboutSystemCard` was
/// fixed) its own "Catalog" stat, but not Dashboard's platform breakdown
/// (`Platform.games`, filtering raw `catalogItems` directly instead of
/// going through `visibleCatalogItems`) or Browse Catalog
/// (`CatalogBrowseViewModel.apply` never checked `isHidden` at all).
struct HiddenCatalogItemVisibilityTests {
    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-hidden-visibility-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makePlatform(_ context: ModelContext) -> Platform {
        let platform = Platform(slug: "nes", name: "Nintendo Entertainment System", shortName: "NES", manufacturer: "Nintendo", generation: 3)
        context.insert(platform)
        return platform
    }

    // MARK: - Platform

    @MainActor
    @Test func gamesConsolesAndAccessoriesExcludeHiddenItemsByDefault() throws {
        let context = try freshContext()
        let platform = makePlatform(context)

        let realGame = CatalogItem(slug: "nes-real-game", kind: .game, name: "Real Game")
        realGame.platform = platform
        let hiddenGame = CatalogItem(slug: "nes-hidden-game", kind: .game, name: "Hidden Game")
        hiddenGame.platform = platform
        hiddenGame.isHidden = true
        let hiddenConsole = CatalogItem(slug: "nes-console", kind: .console, name: "NES Console")
        hiddenConsole.platform = platform
        hiddenConsole.isHidden = true
        for item in [realGame, hiddenGame, hiddenConsole] { context.insert(item) }

        #expect(platform.games.map(\.slug) == ["nes-real-game"])
        #expect(platform.consoles.isEmpty)
        #expect(platform.visibleCatalogItems().count == 1)
        #expect(platform.visibleCatalogItems(includeHidden: true).count == 3)
    }

    // MARK: - CatalogBrowseViewModel

    @MainActor
    @Test func applyExcludesHiddenItemsUnlessShowHiddenIsOn() throws {
        let context = try freshContext()
        let platform = makePlatform(context)
        let visible = CatalogItem(slug: "nes-visible", kind: .game, name: "Visible")
        visible.platform = platform
        let hidden = CatalogItem(slug: "nes-hidden", kind: .game, name: "Hidden")
        hidden.platform = platform
        hidden.isHidden = true
        context.insert(visible)
        context.insert(hidden)

        let viewModel = CatalogBrowseViewModel()
        #expect(viewModel.apply(to: [visible, hidden]).map(\.slug) == ["nes-visible"])

        viewModel.showHidden = true
        let withHidden = Set(viewModel.apply(to: [visible, hidden]).map(\.slug))
        #expect(withHidden == ["nes-visible", "nes-hidden"])
    }
}
