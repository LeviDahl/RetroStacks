import SwiftUI
import SwiftData

@main
struct RetroStacksApp: App {
    /// One container for the whole app. `SampleData` seeds it instantly on first
    /// launch so the UI has content; `CatalogSyncService` then reconciles it with
    /// the data feed in the background.
    let container: ModelContainer

    init() {
        Self.configureImageCache()
        do {
            let container = try ModelContainer(
                for: Platform.self, CatalogItem.self, CollectionItem.self
            )
            self.container = container
            // `App.init()` runs on the main actor, so the seed is safe here.
            SampleData.seedIfNeeded(container.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// `AsyncImage` uses `URLSession.shared` → `URLCache.shared`. The default is
    /// tiny; give remote catalog art a real on-disk cache so it loads once and
    /// then stays instant (and offline-friendly). Wikimedia sends long-lived
    /// cache headers, so this is honored.
    private static func configureImageCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await CatalogSyncService.shared.sync(into: container.mainContext)
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1240, height: 820)
        .commands {
            SidebarCommands()
        }
        #endif
    }
}
