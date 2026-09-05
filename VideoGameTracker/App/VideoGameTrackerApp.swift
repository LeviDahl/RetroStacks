import SwiftUI
import SwiftData

@main
struct VideoGameTrackerApp: App {
    /// One container for the whole app. Seeded with mock data on first launch;
    /// swap `SampleData.seedIfNeeded` for a network sync later.
    let container: ModelContainer

    init() {
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

    var body: some Scene {
        WindowGroup {
            RootView()
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
