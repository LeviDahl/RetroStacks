import Foundation
import Observation
import SwiftData

/// Aggregates the pricing adapters into one canonical `PriceGuide` per catalog
/// item, with fallback/redundancy and a short in-memory cache.
///
/// Priority = provider array order. For each `condition|kind` slot the first
/// provider that has a value wins; lower-priority providers backfill the rest.
/// If every network provider fails, the built-in guide's echoed values still
/// come through, so the UI degrades to "last known" rather than empty.
@MainActor
@Observable
final class PricingService {
    private(set) var providers: [any PricingProvider]
    private let ttl: TimeInterval
    private var cache: [String: (guide: PriceGuide, storedAt: Date)] = [:]

    /// App-wide default. Swap for injected instances in tests / previews.
    static let shared = PricingService.makeDefault()

    init(providers: [any PricingProvider], ttl: TimeInterval = 6 * 3600) {
        self.providers = providers
        self.ttl = ttl
    }

    static func makeDefault() -> PricingService {
        PricingService(providers: [
            PriceChartingProvider(),   // gold standard — active once a token is set
            EbayBrowseProvider(),      // redundancy for common items
            GGDealsProvider(),         // digital/modern titles
            SampleGuideProvider(),     // always-on offline fallback
        ])
    }

    /// Providers that can actually run right now.
    var activeProviderNames: [String] {
        providers.filter(\.isConfigured).map(\.displayName)
    }

    var hasLiveProvider: Bool {
        providers.contains { $0.isConfigured && $0.id != .sampleGuide }
    }

    // MARK: - Reads

    /// Merged guide for an item. Served from cache within `ttl` unless `forceRefresh`.
    func priceGuide(for item: CatalogItem, forceRefresh: Bool = false) async -> PriceGuide {
        let key = item.slug
        if !forceRefresh,
           let hit = cache[key],
           Date().timeIntervalSince(hit.storedAt) < ttl {
            return hit.guide
        }

        let query = makeQuery(for: item)
        var reports: [ProviderPriceReport] = []
        for provider in providers where provider.isConfigured {
            do {
                let report = try await provider.priceReport(for: query)
                if !report.points.isEmpty { reports.append(report) }
            } catch {
                continue   // redundancy: try the next provider
            }
        }

        let guide = Self.merge(reports, catalogSlug: item.slug, fallback: query.fallbackPoints)
        cache[key] = (guide, Date())
        return guide
    }

    // MARK: - Refresh (writes back to the model's cached fields)

    /// Fetch fresh prices and persist them onto the catalog item so lists,
    /// stats, and offline use stay fast and synchronous.
    @discardableResult
    func refresh(_ item: CatalogItem, in context: ModelContext) async -> PriceGuide {
        let guide = await priceGuide(for: item, forceRefresh: true)
        apply(guide, to: item)
        try? context.save()
        return guide
    }

    func apply(_ guide: PriceGuide, to item: CatalogItem) {
        if let v = guide.value(for: .loose)         { item.estimatedValueLoose = v }
        if let v = guide.value(for: .completeInBox)  { item.estimatedValueComplete = v }
        if let v = guide.value(for: .new)            { item.estimatedValueSealed = v }
        if let v = guide.value(for: .graded)         { item.estimatedValueGraded = v }
        if let vol = guide.salesVolumeYearly         { item.salesVolumeYearly = vol }
        item.priceGuideProviderID = guide.primaryProvider.rawValue
        item.priceGuideUpdatedAt = guide.asOf
    }

    // MARK: - Query construction

    private func makeQuery(for item: CatalogItem) -> PriceQuery {
        PriceQuery(
            title: item.name,
            platform: item.platform?.name ?? item.platformShortName,
            upc: item.upc,
            catalogSlug: item.slug,
            knownProductIDs: [:],
            fallbackPoints: Self.cachedPoints(of: item)
        )
    }

    /// The item's own last-known values, as `PricePoint`s for the offline provider.
    static func cachedPoints(of item: CatalogItem) -> [PricePoint] {
        let stamp = item.priceGuideUpdatedAt ?? .now
        var points: [PricePoint] = []
        func add(_ amount: Decimal?, _ condition: MarketCondition) {
            guard let amount, amount > 0 else { return }
            points.append(PricePoint(condition: condition, amount: amount,
                                     observedAt: stamp, sampleSize: item.salesVolumeYearly))
        }
        add(item.estimatedValueLoose, .loose)
        add(item.estimatedValueComplete, .completeInBox)
        add(item.estimatedValueSealed, .new)
        add(item.estimatedValueGraded, .graded)
        return points
    }

    // MARK: - Merge

    static func merge(
        _ reports: [ProviderPriceReport],
        catalogSlug: String?,
        fallback: [PricePoint]
    ) -> PriceGuide {
        guard !reports.isEmpty else {
            return PriceGuide(
                catalogSlug: catalogSlug,
                points: fallback,
                salesVolumeYearly: fallback.compactMap(\.sampleSize).max(),
                asOf: fallback.map(\.observedAt).max() ?? .now,
                primaryProvider: .sampleGuide,
                contributingProviders: fallback.isEmpty ? [] : [.sampleGuide],
                externalProductIDs: [:]
            )
        }

        var chosen: [String: PricePoint] = [:]      // "condition|kind" → point
        var contributing: [PricingProviderID] = []
        var externalIDs: [String: String] = [:]
        var salesVolume: Int?

        for report in reports {                      // already in priority order
            if !contributing.contains(report.provider) { contributing.append(report.provider) }
            if let pid = report.matchedProductID { externalIDs[report.provider.rawValue] = pid }
            if salesVolume == nil { salesVolume = report.salesVolumeYearly }
            for point in report.points where chosen[point.id] == nil {
                chosen[point.id] = point
            }
        }

        let points = chosen.values.sorted {
            ($0.condition.sortIndex, $0.kind.rawValue) < ($1.condition.sortIndex, $1.kind.rawValue)
        }
        return PriceGuide(
            catalogSlug: catalogSlug,
            points: points,
            salesVolumeYearly: salesVolume,
            asOf: reports.map(\.retrievedAt).max() ?? .now,
            primaryProvider: reports[0].provider,
            contributingProviders: contributing,
            externalProductIDs: externalIDs
        )
    }
}
