// Regenerates api/data/catalog.json from the app's SampleData — the current
// source of truth for the sample catalog. Run when SampleData changes:
//
//   cd apple/RetroStacks
//   swiftc -parse-as-library -swift-version 6 \
//     ../../api/build/export-catalog.swift \
//     Models/*.swift Services/CollectionStats.swift Services/SampleData.swift \
//     Services/Pricing/*.swift Views/Components/Formatting.swift \
//     -o /tmp/export-catalog && /tmp/export-catalog > ../../api/data/catalog.json
//
// (A follow-up will invert this so catalog.json is primary and SampleData
// decodes it — see api/README.md.)

import Foundation
import SwiftData

struct FeedPlatform: Encodable {
    var slug, name, shortName, manufacturer: String
    var generation: Int
    var releaseYearNA, discontinuedYearNA: Int?
    var summary, iconSystemName: String
    var regions: [String]
}

struct FeedItem: Encodable {
    var slug, platformSlug, kind, name: String
    var variant: String?
    var releaseYearNA: Int?
    var manufacturerOrPublisher, developer, genre, upc: String?
    var summary: String
    var imageURL, imageCredit, imageLicense: String?
    var priceLoose, priceComplete, priceSealed, priceGraded: Decimal?
    var salesVolumeYearly: Int?
}

struct Feed: Encodable {
    var version: String
    var generatedAt: String
    var platforms: [FeedPlatform]
    var items: [FeedItem]
}

@main
struct Export {
    @MainActor
    static func main() throws {
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        SampleData.seed(into: ctx)

        let platforms = try ctx.fetch(FetchDescriptor<Platform>())
            .sorted { ($0.generation, $0.name) < ($1.generation, $1.name) }
            .map { p in
                FeedPlatform(
                    slug: p.slug, name: p.name, shortName: p.shortName,
                    manufacturer: p.manufacturer, generation: p.generation,
                    releaseYearNA: p.releaseYearNA, discontinuedYearNA: p.discontinuedYearNA,
                    summary: p.summary, iconSystemName: p.iconSystemName,
                    regions: p.regionsAvailable.map(\.rawValue)
                )
            }

        let items = try ctx.fetch(FetchDescriptor<CatalogItem>())
            .sorted { $0.slug < $1.slug }
            .map { c in
                FeedItem(
                    slug: c.slug,
                    platformSlug: c.platform?.slug ?? "",
                    kind: c.kind.rawValue,
                    name: c.name,
                    variant: c.variant,
                    releaseYearNA: c.releaseYearNA,
                    manufacturerOrPublisher: c.manufacturerOrPublisher,
                    developer: c.developer,
                    genre: c.genre,
                    upc: c.upc,
                    summary: c.summary,
                    imageURL: c.imageURLString,
                    imageCredit: c.imageCredit,
                    imageLicense: c.imageLicense,
                    priceLoose: c.estimatedValueLoose,
                    priceComplete: c.estimatedValueComplete,
                    priceSealed: c.estimatedValueSealed,
                    priceGraded: c.estimatedValueGraded,
                    salesVolumeYearly: c.salesVolumeYearly
                )
            }

        let feed = Feed(
            version: "1",
            generatedAt: ISO8601DateFormatter().string(from: .now),
            platforms: platforms,
            items: items
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(feed))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
