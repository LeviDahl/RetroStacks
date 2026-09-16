import Foundation
import SwiftData

/// First-launch seed + preview data.
///
/// The data itself is authored as JSON and lives in `Resources/` —
/// `CatalogSeed.json` (the curated catalog, kept in sync with
/// `api/data/curated.json` by `api/build/sync-seed.mjs`) and
/// `SampleCollection.json` (the demo collection). `CatalogSeedStore` does the
/// decoding + inserting; this type is just the entry points the app and the
/// `#Preview` blocks call.
enum SampleData {

    // MARK: - Container factories

    /// A fully populated in-memory container for previews and `#Preview` blocks.
    /// Includes the demo collection — previews want a populated UI to look at,
    /// unlike a real install (see `seedIfNeeded`).
    @MainActor
    static func previewContainer() -> ModelContainer {
        // In-memory config with a fixed schema; can't fail.
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        seed(into: container.mainContext, includeSampleCollection: true)
        return container
    }

    // MARK: - Seeding

    /// On first launch (empty store) inserts the catalog. `includeSampleCollection`
    /// is the caller's call: `RetroStacksApp` passes `true` only for
    /// `-uiTesting` runs, which need the demo collection's known, stable
    /// content for existing tests to assert against (e.g. the SNES rows
    /// `NavigationTests` looks for) — a real install passes `false` and
    /// starts with nothing "owned," not a demo collection standing in for
    /// the user's actual games. On later launches this just re-applies the
    /// seed's image URLs / platform icons, so an install that predates a
    /// content change picks it up without a wipe. Safe every launch.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext, includeSampleCollection: Bool) {
        let count = (try? context.fetchCount(FetchDescriptor<Platform>())) ?? 0
        if count == 0 {
            seed(into: context, includeSampleCollection: includeSampleCollection)
        } else if let catalog = try? CatalogSeedStore.bundledCatalog() {
            CatalogSeedStore.reapplyMedia(from: catalog, into: context)
        }
    }

    /// Decode the bundled seed and insert it. Assumes an empty store.
    @MainActor
    static func seed(into context: ModelContext, includeSampleCollection: Bool) {
        do {
            let catalog = try CatalogSeedStore.bundledCatalog()
            let sample = includeSampleCollection ? CatalogSeedStore.bundledSampleCollection() : nil
            CatalogSeedStore.insert(catalog, sampleCollection: sample, into: context)
        } catch {
            // A missing/broken bundled seed shouldn't crash the app — the store
            // stays empty and `CatalogSyncService` fills it from the data feed on
            // the next launch. In DEBUG we want to know immediately.
            assertionFailure("SampleData seed failed: \(error)")
        }
    }
}
