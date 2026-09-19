import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// The summaries moved off the main actor after a real `sample` of the live
/// app (2026-09-19) put them at ~6s of a 30s clicking window — this locks
/// down that the background result is identical to the synchronous builder's,
/// including the single-pass kind partition that replaced separate
/// `.games`/`.consoles`/`.accessories` walks.
struct CollectionSummariesActorTests {
    @MainActor
    private func seed() throws -> ModelContainer {
        let url = URL.temporaryDirectory.appending(path: "rs-summaries-actor-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        let platform = Platform(slug: "nes", name: "NES", shortName: "NES", manufacturer: "Nintendo", generation: 3)
        context.insert(platform)
        var owned: CatalogItem?
        for (i, kind) in [ItemKind.game, .game, .game, .console, .accessory].enumerated() {
            let item = CatalogItem(slug: "item-\(i)", kind: kind, name: "Item \(i)")
            item.platform = platform
            context.insert(item)
            if i == 0 { owned = item }
        }
        if let owned { context.insert(CollectionItem(catalogItem: owned, status: .owned)) }
        try context.save()
        return container
    }

    @Test @MainActor func backgroundSummariesMatchTheSynchronousBuilder() async throws {
        let container = try seed()
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        let expected = CollectionStatsBuilder.systemSummaries(from: items, status: .owned)

        let actual = try await CollectionSummariesActor(modelContainer: container).systemSummaries(status: .owned)

        #expect(actual.count == 1)
        #expect(actual.map(\.platformSlug) == expected.map(\.platformSlug))
        #expect(actual.first?.catalogGameCount == 3)
        #expect(actual.first?.catalogConsoleCount == 1)
        #expect(actual.first?.catalogAccessoryCount == 1)
        #expect(actual.first?.ownedGameCount == 1)
        #expect(actual.first?.catalogGameCount == expected.first?.catalogGameCount)
    }

    /// Regression: a `@ModelActor` built from a `@MainActor` caller runs on
    /// the main thread, which silently undid the whole off-main move (live
    /// `sample`, 2026-09-19). Called from the main actor here, on purpose.
    @Test @MainActor func actorBuiltViaHelperRunsOffTheMainThread() async throws {
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        #expect(await CollectionSummariesActor.runsOnMainThread(container: container) == false)
    }
}
