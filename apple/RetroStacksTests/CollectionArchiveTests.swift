import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// `CollectionArchive.Entry.init(item:)` / `.apply(to:catalogBySlug:)` are the
/// one field mapping shared by the local JSON backup, `CollectionArchive.restore`,
/// and `SyncCoordinator`/`SupabaseCollectionSyncEngine` — a regression here
/// silently corrupts either the backup format or collection sync. Extracted
/// from what used to be two separate 20-line inline blocks (see git history);
/// this locks the round trip down now that they're shared code.
struct CollectionArchiveTests {

    @MainActor
    private func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "rs-archive-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    @MainActor
    @Test func entryRoundTripsEveryFieldOntoAFreshItem() throws {
        let context = try freshContext()
        let catalogItem = CatalogItem(slug: "snes-chrono-trigger", kind: .game, name: "Chrono Trigger")
        context.insert(catalogItem)

        let original = CollectionItem(
            catalogItem: catalogItem,
            status: .owned,
            condition: .veryGood,
            completeness: .completeInBox,
            hasBox: true, hasManual: true, hasInserts: false, hasOriginalPackaging: true,
            gradingCompany: .wata,
            gradeScore: 9.4,
            pricePaid: 45.00,
            dateAcquired: Date(timeIntervalSince1970: 1_700_000_000),
            acquisitionSource: .onlineMarketplace,
            estimatedValueOverride: 120.00,
            storageLocation: "Shelf B",
            notes: "Mint condition, sealed sleeve",
            photoData: [],
            playStatus: .completed,
            dateAdded: Date(timeIntervalSince1970: 1_690_000_000)
        )
        original.updatedAt = Date(timeIntervalSince1970: 1_705_000_000)
        context.insert(original)
        try context.save()

        let entry = CollectionArchive.Entry(item: original)

        let target = CollectionItem(exportID: entry.exportID)
        context.insert(target)
        entry.apply(to: target, catalogBySlug: ["snes-chrono-trigger": catalogItem])

        #expect(target.catalogItem?.slug == "snes-chrono-trigger")
        #expect(target.status == .owned)
        #expect(target.condition == .veryGood)
        #expect(target.completeness == .completeInBox)
        #expect(target.hasBox == true)
        #expect(target.hasManual == true)
        #expect(target.hasInserts == false)
        #expect(target.hasOriginalPackaging == true)
        #expect(target.gradingCompany == .wata)
        #expect(target.gradeScore == 9.4)
        #expect(target.pricePaid == 45.00)
        #expect(target.dateAcquired == original.dateAcquired)
        #expect(target.acquisitionSource == .onlineMarketplace)
        #expect(target.estimatedValueOverride == 120.00)
        #expect(target.storageLocation == "Shelf B")
        #expect(target.notes == "Mint condition, sealed sleeve")
        #expect(target.playStatus == .completed)
        #expect(target.dateAdded == original.dateAdded)
        #expect(target.updatedAt == original.updatedAt)
    }

    @MainActor
    @Test func makeFiltersOutSoftDeletedItems() {
        let live = CollectionItem(status: .owned, notes: "keep me")
        let deleted = CollectionItem(status: .owned, notes: "gone")
        deleted.markDeleted()

        let archive = CollectionArchive.make(from: [live, deleted])
        #expect(archive.entries.count == 1)
        #expect(archive.entries.first?.notes == "keep me")
    }
}
