import SwiftUI
import SwiftData

@main
struct RetroStacksApp: App {
    /// One container for the whole app. `SampleData` seeds it instantly on first
    /// launch so the UI has content; `CatalogSyncService` then reconciles it with
    /// the data feed in the background.
    let container: ModelContainer

    /// UI tests (`RetroStacksUITests`) pass `-uiTesting` so every run gets a
    /// fresh, deterministic, in-memory store — the seed data, nothing carried
    /// over from a previous run or from actually using the app on this Mac.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        Self.configureImageCache()
        if Self.isUITesting {
            // The in-memory ModelContainer below already gives every run a
            // fresh collection/catalog, but @AppStorage (view-option toggles,
            // filters, sort order, the platform-breakdown visibility switch)
            // reads real UserDefaults.standard, which persists across launches
            // regardless of the store. Without this, a UI test's result can
            // depend on whatever state a *previous* run — or a developer
            // manually poking at the app — left behind. Full reset for a
            // truly clean slate every time.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
        }
        do {
            let configuration = Self.isUITesting
                ? ModelConfiguration(isStoredInMemoryOnly: true)
                : ModelConfiguration()
            let container = try ModelContainer(
                for: Platform.self, CatalogItem.self, CollectionItem.self,
                configurations: configuration
            )
            self.container = container
            // `App.init()` runs on the main actor, so the seed is safe here.
            // Sample *collection* data only for -uiTesting — existing tests
            // assert against its known, stable content (e.g. SNES rows in
            // NavigationTests). A real install gets the catalog only, no
            // demo "owned" games standing in for the user's actual collection.
            SampleData.seedIfNeeded(container.mainContext, includeSampleCollection: Self.isUITesting)
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
                    // Keep UI test runs deterministic — no real network sync
                    // racing the test against its in-memory seed.
                    guard !Self.isUITesting else { return }
                    await CatalogSyncService.shared.sync(into: container.mainContext)
                }
                .task {
                    // No-ops while signed out — see `SyncCoordinator`.
                    guard !Self.isUITesting else { return }
                    await SyncCoordinator.shared.sync(into: container.mainContext)
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
