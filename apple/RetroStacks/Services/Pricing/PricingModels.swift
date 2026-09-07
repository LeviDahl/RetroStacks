import Foundation

// MARK: - Canonical pricing schema
//
// This is our provider-agnostic pricing vocabulary. The shape is adapted from
// the PriceCharting Prices API (the de-facto standard for retro game values —
// https://www.pricecharting.com/api-documentation) so their data maps in with
// almost no translation, but nothing here is PriceCharting-specific: each
// provider adapter maps its own API onto these types.
//
// Deliberately free of SwiftUI / SwiftData imports so it can be lifted into a
// shared Swift package, or re-implemented server-side as the API contract, with
// no changes. The one app-coupled bit (`Completeness` bridge) is fenced off at
// the bottom.

/// A price tier — the condition/completeness a price refers to.
nonisolated enum MarketCondition: String, Codable, Sendable, CaseIterable, Identifiable {
    case loose                          // item only, no box or manual
    case completeInBox = "cib"          // item + box + manual
    case new                            // factory sealed
    case graded                         // sealed & professionally graded (WATA / VGA)
    case boxOnly = "box_only"
    case manualOnly = "manual_only"

    var id: String { rawValue }

    /// Stable display order for UI and merge tie-breaks.
    var sortIndex: Int {
        switch self {
        case .loose: 0
        case .completeInBox: 1
        case .new: 2
        case .graded: 3
        case .boxOnly: 4
        case .manualOnly: 5
        }
    }

    var displayName: String {
        switch self {
        case .loose: "Loose"
        case .completeInBox: "Complete in Box"
        case .new: "Sealed"
        case .graded: "Graded"
        case .boxOnly: "Box Only"
        case .manualOnly: "Manual Only"
        }
    }

    /// The four tiers the app surfaces by default.
    static let primary: [MarketCondition] = [.loose, .completeInBox, .new, .graded]
}

/// What a number *means* — a market value vs. a dealer spread vs. a live listing.
nonisolated enum PriceKind: String, Codable, Sendable {
    case marketValue        // "what it's worth" — the headline number
    case retailBuy          // recommended price a dealer pays a customer
    case retailSell         // recommended price a dealer charges a customer
    case listingLow         // cheapest active listing seen
    case soldMedian         // median of recent completed sales
    case gamestopPreowned   // GameStop pre-owned shelf price
}

/// Identifies a pricing source. A struct (not an enum) so new providers can be
/// added — including server-side — without editing this file.
nonisolated struct PricingProviderID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }

    // Encode as a bare string (`"sample_guide"`), not `{"rawValue": …}`, so the
    // JSON wire format matches the data feed.
    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let priceCharting = PricingProviderID("pricecharting")
    static let ebay          = PricingProviderID("ebay")
    static let ggDeals       = PricingProviderID("gg_deals")
    static let sampleGuide   = PricingProviderID("sample_guide")
    static let manual        = PricingProviderID("manual")

    var displayName: String {
        switch self {
        case .priceCharting: "PriceCharting"
        case .ebay: "eBay"
        case .ggDeals: "GG.deals"
        case .sampleGuide: "Built-in Guide"
        case .manual: "Manual Entry"
        default: rawValue
        }
    }
}

/// One price for one condition from one source.
nonisolated struct PricePoint: Codable, Sendable, Equatable, Identifiable {
    var condition: MarketCondition
    var kind: PriceKind
    var amount: Decimal
    var currencyCode: String
    var observedAt: Date
    /// Signal behind the number — e.g. yearly sales volume, or # of listings.
    var sampleSize: Int?
    var sourceURL: URL?

    var id: String { "\(condition.rawValue)|\(kind.rawValue)" }

    init(
        condition: MarketCondition,
        kind: PriceKind = .marketValue,
        amount: Decimal,
        currencyCode: String = "USD",
        observedAt: Date = .now,
        sampleSize: Int? = nil,
        sourceURL: URL? = nil
    ) {
        self.condition = condition
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.observedAt = observedAt
        self.sampleSize = sampleSize
        self.sourceURL = sourceURL
    }

    /// Build from an integer minor-unit amount (PriceCharting pennies, etc.).
    /// Returns nil for non-positive input so "no data" (0) is dropped.
    static func fromMinorUnits(
        _ minor: Int?,
        condition: MarketCondition,
        kind: PriceKind = .marketValue,
        currencyCode: String = "USD",
        observedAt: Date,
        sampleSize: Int? = nil,
        sourceURL: URL? = nil
    ) -> PricePoint? {
        guard let minor, minor > 0 else { return nil }
        return PricePoint(
            condition: condition, kind: kind,
            amount: Decimal(minor) / 100,
            currencyCode: currencyCode, observedAt: observedAt,
            sampleSize: sampleSize, sourceURL: sourceURL
        )
    }
}

/// Raw output of a single adapter for a single item.
nonisolated struct ProviderPriceReport: Sendable, Equatable {
    var provider: PricingProviderID
    var matchedProductID: String?
    var matchedTitle: String?
    var matchedPlatform: String?
    var points: [PricePoint]
    var salesVolumeYearly: Int?
    var retrievedAt: Date

    init(
        provider: PricingProviderID,
        matchedProductID: String? = nil,
        matchedTitle: String? = nil,
        matchedPlatform: String? = nil,
        points: [PricePoint] = [],
        salesVolumeYearly: Int? = nil,
        retrievedAt: Date = .now
    ) {
        self.provider = provider
        self.matchedProductID = matchedProductID
        self.matchedTitle = matchedTitle
        self.matchedPlatform = matchedPlatform
        self.points = points
        self.salesVolumeYearly = salesVolumeYearly
        self.retrievedAt = retrievedAt
    }
}

/// The merged, consumer-facing result for one catalog item.
nonisolated struct PriceGuide: Codable, Sendable, Equatable {
    var catalogSlug: String?
    var points: [PricePoint]
    var salesVolumeYearly: Int?
    var asOf: Date
    var primaryProvider: PricingProviderID
    var contributingProviders: [PricingProviderID]
    /// providerID.rawValue → that provider's product id, cached for fast re-lookup.
    var externalProductIDs: [String: String]

    static func unavailable(catalogSlug: String?) -> PriceGuide {
        PriceGuide(
            catalogSlug: catalogSlug, points: [], salesVolumeYearly: nil,
            asOf: .now, primaryProvider: .sampleGuide,
            contributingProviders: [], externalProductIDs: [:]
        )
    }

    func value(for condition: MarketCondition, kind: PriceKind = .marketValue) -> Decimal? {
        points.first { $0.condition == condition && $0.kind == kind }?.amount
    }

    func point(for condition: MarketCondition, kind: PriceKind = .marketValue) -> PricePoint? {
        points.first { $0.condition == condition && $0.kind == kind }
    }

    /// `marketValue` points for the four primary tiers, in display order.
    var headlineRows: [PricePoint] {
        MarketCondition.primary.compactMap { point(for: $0) }
    }

    var hasAnyValue: Bool { !points.isEmpty }
}

/// What the aggregator hands each adapter.
nonisolated struct PriceQuery: Sendable {
    var title: String
    var platform: String
    var upc: String?
    var catalogSlug: String?
    /// Cached external ids so a provider can do an exact lookup instead of search.
    var knownProductIDs: [String: String]
    /// Values we already hold (our own cache / seed). Offline providers echo
    /// these; network providers ignore them.
    var fallbackPoints: [PricePoint]

    init(
        title: String,
        platform: String,
        upc: String? = nil,
        catalogSlug: String? = nil,
        knownProductIDs: [String: String] = [:],
        fallbackPoints: [PricePoint] = []
    ) {
        self.title = title
        self.platform = platform
        self.upc = upc
        self.catalogSlug = catalogSlug
        self.knownProductIDs = knownProductIDs
        self.fallbackPoints = fallbackPoints
    }
}

// MARK: - App bridge (the only RetroStacks-coupled part)

nonisolated extension Completeness {
    /// Map the collection-item completeness axis onto a pricing tier.
    /// "Boxed, no manual" has no PriceCharting equivalent → treated as CIB.
    var marketCondition: MarketCondition {
        switch self {
        case .sealed: .new
        case .graded: .graded
        case .completeInBox: .completeInBox
        case .boxedNoManual: .completeInBox
        case .loose: .loose
        }
    }
}
