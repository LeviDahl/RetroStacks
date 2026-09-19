import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Real bug, user-reported 2026-09-19: `QuickAddSheet` (the "+" add modal)
/// only ever set `completeness` — `CollectionActions.add` had no
/// `hasBox`/`hasManual` parameters at all, so picking "CIB" in the modal
/// left the actual checklist booleans `false` regardless. Locks down that
/// `add` now persists whatever it's given, since `completeness` is what
/// picks the PriceCharting-sourced price tier (`CatalogItem
/// .referenceValue(for:)`) and the checklist booleans are what the full
/// edit view's Box/Manual toggles actually read — both need to reflect
/// reality, not just one of them.
struct CollectionActionsTests {
    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-collection-actions-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    @MainActor
    private func game(in context: ModelContext) -> CatalogItem {
        let platform = Platform(
            slug: "nes", name: "Nintendo Entertainment System", shortName: "NES",
            manufacturer: "Nintendo", generation: 3
        )
        context.insert(platform)
        let item = CatalogItem(slug: "zelda", kind: .game, name: "Zelda")
        item.platform = platform
        context.insert(item)
        return item
    }

    @Test @MainActor func addPersistsHasBoxAndHasManualWhenGiven() throws {
        let context = try freshContext()
        let item = game(in: context)

        let entry = CollectionActions.add(
            item, status: .owned, completeness: .completeInBox, condition: .good,
            hasBox: true, hasManual: true, in: context
        )

        #expect(entry.hasBox == true)
        #expect(entry.hasManual == true)
        #expect(entry.completeness == .completeInBox)
    }

    @Test @MainActor func addDefaultsHasBoxAndHasManualToFalse() throws {
        let context = try freshContext()
        let item = game(in: context)

        let entry = CollectionActions.add(item, status: .owned, completeness: .loose, condition: .good, in: context)

        #expect(entry.hasBox == false)
        #expect(entry.hasManual == false)
    }

    @Test @MainActor func addCanRecordBoxWithoutManualOrViceVersa() throws {
        let context = try freshContext()
        let item = game(in: context)

        let boxOnly = CollectionActions.add(
            item, status: .owned, completeness: .boxedNoManual, hasBox: true, hasManual: false, in: context
        )
        #expect(boxOnly.hasBox == true)
        #expect(boxOnly.hasManual == false)
    }
}
