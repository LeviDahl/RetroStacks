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
    @MainActor
    static func previewContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        seed(into: container.mainContext)
        return container
    }

    // MARK: - Seeding

    /// On first launch (empty store) inserts the full seed. On later launches it
    /// just re-applies the seed's image URLs / platform icons, so an install that
    /// predates a content change picks it up without a wipe. Safe every launch.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Platform>())) ?? 0
        if count == 0 {
            seed(into: context)
        } else if let catalog = try? CatalogSeedStore.bundledCatalog() {
            CatalogSeedStore.reapplyMedia(from: catalog, into: context)
        }
    }

    /// Decode the bundled seed and insert it. Assumes an empty store.
    @MainActor
    static func seed(into context: ModelContext) {
        do {
            let catalog = try CatalogSeedStore.bundledCatalog()
            let sample = CatalogSeedStore.bundledSampleCollection()
            CatalogSeedStore.insert(catalog, sampleCollection: sample, into: context)
        } catch {
            // A missing/broken bundled seed shouldn't crash the app — the store
            // stays empty and `CatalogSyncService` fills it from the data feed on
            // the next launch. In DEBUG we want to know immediately.
            assertionFailure("SampleData seed failed: \(error)")
        }
    }
}
