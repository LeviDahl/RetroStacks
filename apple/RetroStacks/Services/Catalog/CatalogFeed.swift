import Foundation

/// Decodable mirrors of the static feed (`v1/catalog.json`, `v1/price-guide.json`).
/// Field names match `api/build/build.mjs` output.

nonisolated struct CatalogFeed: Decodable, Sendable {
    var version: String
    var generatedAt: Date
    var platforms: [FeedPlatform]
    var items: [FeedItem]
}

nonisolated struct FeedPlatform: Decodable, Sendable {
    var slug: String
    var name: String
    var shortName: String
    var manufacturer: String
    var generation: Int
    var releaseYearNA: Int?
    var discontinuedYearNA: Int?
    var summary: String
    var iconSystemName: String
    var regions: [String]
}

nonisolated struct FeedItem: Decodable, Sendable {
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
    /// Only the ~66 curated entries carry a hand-written summary; the ~3,500
    /// imported games don't (see `ingest/libretro.mjs` / `ingest/igdb.mjs`).
    var summary: String?
    var imageURL: String?
    var imageCredit: String?
    var imageLicense: String?
}

nonisolated struct PriceGuideFeed: Decodable, Sendable {
    var version: String
    var generatedAt: Date
    var guides: [String: PriceGuide]
}

// MARK: - Decoding

extension JSONDecoder {
    /// Decoder for the data feed: ISO-8601 dates, tolerant of fractional seconds
    /// (which `Date().toISOString()` in the build script emits). Uses the
    /// `Sendable` `Date.ISO8601FormatStyle`, not `ISO8601DateFormatter`.
    nonisolated static var retroStacksFeed: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: d.codingPath, debugDescription: "Bad ISO-8601 date: \(raw)")
            )
        }
        return decoder
    }
}
