import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Covers the inverted seed path: JSON in `Resources/` → `CatalogSeedStore` →
/// SwiftData. Fixtures live in `Fixtures/`, loaded relative to this source file
/// so no test-bundle resource wiring is needed.
///
/// `.serialized`: a second *in-memory* `ModelContainer` for the same schema in
/// one process traps inside SwiftData, so each test gets its own on-disk
/// container in a unique temp location instead.
@Suite(.serialized)
struct CatalogSeedTests {

    // MARK: Fixture loading

    static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    /// The real bundled seed the app ships, reached from the source tree.
    static let bundledSeedURL = URL(filePath: #filePath)
        .deletingLastPathComponent()          // RetroStacksTests
        .deletingLastPathComponent()          // apple
        .appendingPathComponent("RetroStacks/Resources/CatalogSeed.json")

    /// A pristine store per call — its own on-disk file under the temp dir.
    @MainActor
    func freshContext() throws -> ModelContext {
        let url = URL.temporaryDirectory
            .appending(path: "rs-seed-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        return ModelContext(container)
    }

    // MARK: - Success

    @Test func validSeedDecodes() throws {
        let seed = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-valid.json"))
        #expect(seed.platforms.count == 1)
        #expect(seed.items.count == 2)
        #expect(seed.platforms.first?.slug == "snes")
    }

    @MainActor
    @Test func validSeedInsertsAndLinks() throws {
        let context = try freshContext()
        let seed = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-valid.json"))

        CatalogSeedStore.insert(seed, into: context)

        let platforms = try context.fetch(FetchDescriptor<Platform>())
        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        #expect(platforms.count == 1)
        #expect(items.count == 2)

        let game = try #require(items.first { $0.slug == "snes-chrono-trigger" })
        #expect(game.platform?.slug == "snes")
        #expect(game.kind == .game)
        #expect(game.estimatedValueComplete == 450)
        #expect(game.estimatedValueGraded == 22000)
        #expect(game.salesVolumeYearly == 140)
        // Priced items get tagged with the built-in guide so the value card renders.
        #expect(game.priceGuideProviderID == PricingProviderID.sampleGuide.rawValue)
        #expect(game.priceGuideUpdatedAt != nil)

        let console = try #require(items.first { $0.slug == "sns-001" })
        #expect(console.kind == .console)
        #expect(console.salesVolumeYearly == nil)
    }

    @MainActor
    @Test func sampleCollectionInsertsWithRelativeDates() throws {
        let context = try freshContext()
        let seed = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-valid.json"))

        let collectionJSON = Data("""
        { "entries": [
            { "catalogSlug": "snes-chrono-trigger", "status": "owned", "condition": "good",
              "completeness": "completeInBox", "hasBox": true, "pricePaid": 240,
              "acquiredDaysAgo": 140, "addedDaysAgo": 140, "playStatus": "completed" },
            { "catalogSlug": "snes-super-metroid", "status": "wishlist", "addedDaysAgo": 5 },
            { "catalogSlug": "does-not-exist", "status": "owned" }
        ] }
        """.utf8)
        let sample = try CatalogSeedStore.decodeSampleCollection(collectionJSON)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        CatalogSeedStore.insert(seed, sampleCollection: sample, into: context, now: now)

        let entries = try context.fetch(FetchDescriptor<CollectionItem>())
        // The entry pointing at a missing catalog slug is skipped; the wishlist
        // one for a slug not in this fixture's catalog is skipped too.
        #expect(entries.count == 1)

        let owned = try #require(entries.first)
        #expect(owned.status == .owned)
        #expect(owned.catalogItem?.slug == "snes-chrono-trigger")
        #expect(owned.completeness == .completeInBox)
        #expect(owned.pricePaid == 240)
        #expect(owned.playStatus == .completed)
        let expectedAdded = Calendar.current.date(byAdding: .day, value: -140, to: now)!
        #expect(abs(owned.dateAdded.timeIntervalSince(expectedAdded)) < 1)
    }

    @Test func bundledSeedIsWellFormed() throws {
        let data = try Data(contentsOf: Self.bundledSeedURL)
        let seed = try CatalogSeedStore.decodeCatalog(data)

        #expect(seed.platforms.count == 10)
        #expect(seed.items.count == 66)

        let platformSlugs = Set(seed.platforms.map(\.slug))
        for item in seed.items {
            #expect(platformSlugs.contains(item.platformSlug),
                    "item \(item.slug) → unknown platform \(item.platformSlug)")
            #expect(ItemKind(rawValue: item.kind) != nil, "item \(item.slug) bad kind \(item.kind)")
        }
    }

    @MainActor
    @Test func bundledSeedRoundTripsIntoStore() throws {
        let context = try freshContext()
        let seed = try CatalogSeedStore.decodeCatalog(try Data(contentsOf: Self.bundledSeedURL))
        CatalogSeedStore.insert(seed, into: context)

        #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 10)
        #expect(try context.fetchCount(FetchDescriptor<CatalogItem>()) == 66)
        let orphans = try context.fetch(FetchDescriptor<CatalogItem>()).filter { $0.platform == nil }
        #expect(orphans.isEmpty)
    }

    // MARK: - Failure

    @Test func malformedJSONThrows() throws {
        #expect(throws: (any Error).self) {
            _ = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-malformed.json"))
        }
    }

    @Test func malformedJSONThrowsDecodingError() throws {
        let data = try Self.fixture("seed-malformed.json")
        var caught: Error?
        do { _ = try CatalogSeedStore.decodeCatalog(data) } catch { caught = error }
        #expect(caught is DecodingError)
    }

    @Test func missingRequiredFieldThrowsDecodingError() throws {
        let data = try Self.fixture("seed-missing-field.json")
        var caught: Error?
        do { _ = try CatalogSeedStore.decodeCatalog(data) } catch { caught = error }
        guard case .keyNotFound? = caught as? DecodingError else {
            Issue.record("expected DecodingError.keyNotFound, got \(String(describing: caught))")
            return
        }
    }

    @Test func emptySeedThrows() throws {
        #expect(throws: CatalogSeedStore.SeedError.empty) {
            _ = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-empty.json"))
        }
    }

    @Test func danglingPlatformReferenceThrows() throws {
        #expect(throws: CatalogSeedStore.SeedError.danglingPlatformReference(item: "gen-sonic", platform: "genesis")) {
            _ = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-dangling-platform.json"))
        }
    }

    @Test func duplicateSlugThrows() throws {
        #expect(throws: CatalogSeedStore.SeedError.duplicateSlug("dupe")) {
            _ = try CatalogSeedStore.decodeCatalog(try Self.fixture("seed-duplicate-slug.json"))
        }
    }
}
