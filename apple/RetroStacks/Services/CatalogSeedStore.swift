import Foundation
import SwiftData

/// Decodes the bundled first-launch seed — `CatalogSeed.json` (the curated
/// catalog, kept in lockstep with `api/data/curated.json` by
/// `api/build/sync-seed.mjs`) and `SampleCollection.json` (the demo collection,
/// app-only) — and inserts it into SwiftData.
///
/// This is the source of truth for the sample data now: it's authored as JSON,
/// not Swift literals. `SampleData` is a thin wrapper over this.
///
/// `nonisolated` (the target defaults new types to `@MainActor`): decoding runs
/// anywhere; only the SwiftData inserts are `@MainActor`.
nonisolated enum CatalogSeedStore {

    // MARK: - Wire types

    struct CatalogSeed: Decodable, Sendable {
        var platforms: [SeedPlatform]
        var items: [SeedItem]
    }

    struct SeedPlatform: Decodable, Sendable {
        var slug: String
        var name: String
        var shortName: String
        var manufacturer: String
        var generation: Int
        var releaseYearNA: Int?
        var discontinuedYearNA: Int?
        var summary: String
        var iconSystemName: String
        var regions: [String]?
    }

    struct SeedItem: Decodable, Sendable {
        var slug: String
        var platformSlug: String
        var kind: String
        var name: String
        var variant: String?
        var releaseYearNA: Int?
        var manufacturerOrPublisher: String?
        var developer: String?
        var genre: String?
        var upc: String?
        var summary: String?
        var imageURL: String?
        var imageCredit: String?
        var imageLicense: String?
        var priceLoose: Decimal?
        var priceComplete: Decimal?
        var priceSealed: Decimal?
        var priceGraded: Decimal?
        var salesVolumeYearly: Int?
    }

    struct SampleCollectionSeed: Decodable, Sendable {
        var entries: [SeedEntry]
    }

    struct SeedEntry: Decodable, Sendable {
        var catalogSlug: String
        var status: String
        var condition: String?
        var completeness: String?
        var hasBox: Bool?
        var hasManual: Bool?
        var hasInserts: Bool?
        var hasOriginalPackaging: Bool?
        var pricePaid: Decimal?
        var estimatedValueOverride: Decimal?
        var acquisitionSource: String?
        var storageLocation: String?
        var notes: String?
        var playStatus: String?
        var acquiredDaysAgo: Int?
        var addedDaysAgo: Int?
    }

    enum SeedError: Error, Equatable, CustomStringConvertible {
        case resourceMissing(String)
        case empty
        case duplicateSlug(String)
        case danglingPlatformReference(item: String, platform: String)

        var description: String {
            switch self {
            case .resourceMissing(let n): "bundled resource not found: \(n)"
            case .empty: "seed has no platforms or no items"
            case .duplicateSlug(let s): "duplicate slug in seed: \(s)"
            case .danglingPlatformReference(let i, let p):
                "seed item \(i) references unknown platform \(p)"
            }
        }
    }

    // MARK: - Decode

    static func decodeCatalog(_ data: Data) throws -> CatalogSeed {
        let seed = try JSONDecoder().decode(CatalogSeed.self, from: data)
        guard !seed.platforms.isEmpty, !seed.items.isEmpty else { throw SeedError.empty }

        var platformSlugs = Set<String>()
        for p in seed.platforms where !platformSlugs.insert(p.slug).inserted {
            throw SeedError.duplicateSlug(p.slug)
        }
        var itemSlugs = Set<String>()
        for item in seed.items {
            guard itemSlugs.insert(item.slug).inserted else { throw SeedError.duplicateSlug(item.slug) }
            guard platformSlugs.contains(item.platformSlug) else {
                throw SeedError.danglingPlatformReference(item: item.slug, platform: item.platformSlug)
            }
        }
        return seed
    }

    static func decodeSampleCollection(_ data: Data) throws -> SampleCollectionSeed {
        try JSONDecoder().decode(SampleCollectionSeed.self, from: data)
    }

    // MARK: - Bundle access

    static func bundledCatalog(in bundle: Bundle = .main) throws -> CatalogSeed {
        guard let url = bundle.url(forResource: "CatalogSeed", withExtension: "json") else {
            throw SeedError.resourceMissing("CatalogSeed.json")
        }
        return try decodeCatalog(Data(contentsOf: url))
    }

    static func bundledSampleCollection(in bundle: Bundle = .main) -> SampleCollectionSeed? {
        guard
            let url = bundle.url(forResource: "SampleCollection", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let seed = try? decodeSampleCollection(data)
        else { return nil }
        return seed
    }

    // MARK: - Insert

    /// Full first-launch insert: platforms, catalog items (linked), and the
    /// optional demo collection. Assumes an empty store.
    @MainActor
    static func insert(
        _ seed: CatalogSeed,
        sampleCollection: SampleCollectionSeed? = nil,
        into context: ModelContext,
        now: Date = .now
    ) {
        var platformsBySlug: [String: Platform] = [:]
        for sp in seed.platforms {
            let platform = Platform(
                slug: sp.slug, name: sp.name, shortName: sp.shortName,
                manufacturer: sp.manufacturer, generation: sp.generation,
                releaseYearNA: sp.releaseYearNA, discontinuedYearNA: sp.discontinuedYearNA,
                summary: sp.summary, iconSystemName: sp.iconSystemName,
                regionsAvailable: (sp.regions ?? ["NA"]).compactMap(Region.init(rawValue:))
            )
            context.insert(platform)
            platformsBySlug[sp.slug] = platform
        }

        var itemsBySlug: [String: CatalogItem] = [:]
        for si in seed.items {
            let hasPrice = si.priceLoose != nil || si.priceComplete != nil
                || si.priceSealed != nil || si.priceGraded != nil
            let item = CatalogItem(
                slug: si.slug,
                kind: ItemKind(rawValue: si.kind) ?? .game,
                name: si.name,
                variant: si.variant,
                releaseYearNA: si.releaseYearNA,
                manufacturerOrPublisher: si.manufacturerOrPublisher,
                developer: si.developer,
                genre: si.genre,
                upc: si.upc,
                summary: si.summary ?? "",
                imageURLString: si.imageURL,
                imageCredit: si.imageCredit,
                imageLicense: si.imageLicense,
                estimatedValueLoose: si.priceLoose,
                estimatedValueComplete: si.priceComplete,
                estimatedValueSealed: si.priceSealed,
                estimatedValueGraded: si.priceGraded,
                salesVolumeYearly: si.salesVolumeYearly,
                priceGuideProviderID: hasPrice ? PricingProviderID.sampleGuide.rawValue : nil,
                priceGuideUpdatedAt: hasPrice ? now : nil
            )
            item.platform = platformsBySlug[si.platformSlug]
            context.insert(item)
            itemsBySlug[si.slug] = item
        }

        if let sampleCollection {
            insertSampleCollection(sampleCollection, itemsBySlug: itemsBySlug, into: context, now: now)
        }

        try? context.save()
    }

    @MainActor
    private static func insertSampleCollection(
        _ seed: SampleCollectionSeed,
        itemsBySlug: [String: CatalogItem],
        into context: ModelContext,
        now: Date
    ) {
        let cal = Calendar.current
        func daysAgo(_ n: Int?) -> Date? {
            guard let n else { return nil }
            return cal.date(byAdding: .day, value: -n, to: now) ?? now
        }

        for entry in seed.entries {
            guard let catalogItem = itemsBySlug[entry.catalogSlug] else { continue }
            let added = daysAgo(entry.addedDaysAgo) ?? now
            let item = CollectionItem(
                catalogItem: catalogItem,
                status: CollectionStatus(rawValue: entry.status) ?? .owned,
                condition: entry.condition.flatMap(ConditionGrade.init(rawValue:)),
                completeness: entry.completeness.flatMap(Completeness.init(rawValue:)),
                hasBox: entry.hasBox ?? false,
                hasManual: entry.hasManual ?? false,
                hasInserts: entry.hasInserts ?? false,
                hasOriginalPackaging: entry.hasOriginalPackaging ?? false,
                pricePaid: entry.pricePaid,
                dateAcquired: daysAgo(entry.acquiredDaysAgo),
                acquisitionSource: entry.acquisitionSource.flatMap(AcquisitionSource.init(rawValue:)),
                estimatedValueOverride: entry.estimatedValueOverride,
                storageLocation: entry.storageLocation,
                notes: entry.notes ?? "",
                playStatus: entry.playStatus.flatMap(PlayStatus.init(rawValue:)),
                dateAdded: added
            )
            context.insert(item)
        }
    }

    // MARK: - Later-launch media refresh

    /// Re-applies the derived-but-mutable fields (image URLs, platform icons) from
    /// the seed to rows that already exist, so an install seeded before a content
    /// change picks it up without a wipe. Idempotent.
    @MainActor
    static func reapplyMedia(from seed: CatalogSeed, into context: ModelContext) {
        let iconBySlug = Dictionary(seed.platforms.map { ($0.slug, $0.iconSystemName) },
                                    uniquingKeysWith: { a, _ in a })
        if let platforms = try? context.fetch(FetchDescriptor<Platform>()) {
            for platform in platforms {
                if let icon = iconBySlug[platform.slug], platform.iconSystemName != icon {
                    platform.iconSystemName = icon
                }
            }
        }

        let itemBySlug = Dictionary(seed.items.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        if let items = try? context.fetch(FetchDescriptor<CatalogItem>()) {
            for item in items {
                guard let si = itemBySlug[item.slug] else { continue }
                if item.imageURLString != si.imageURL { item.imageURLString = si.imageURL }
                if let credit = si.imageCredit, item.imageCredit != credit { item.imageCredit = credit }
                if let license = si.imageLicense, item.imageLicense != license { item.imageLicense = license }
            }
        }

        if let entries = try? context.fetch(FetchDescriptor<CollectionItem>()) {
            for entry in entries where entry.exportID == nil {
                entry.exportID = UUID()
            }
        }
        if context.hasChanges { try? context.save() }
    }
}
