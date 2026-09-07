import Foundation

/// Serves prices from the static `price-guide.json` feed. Priority provider once
/// the feed is reachable; on any failure the aggregator falls through to
/// `SampleGuideProvider` (the cached/seed values).
///
/// An `actor` so the fetched guide map is cached across lookups without a race.
actor RemotePricingProvider: PricingProvider {
    nonisolated let id = PricingProviderID("retrostacks_feed")
    nonisolated var displayName: String { "RetroStacks" }
    nonisolated var isConfigured: Bool { true }

    private let repository: CatalogRepository
    private let ttl: TimeInterval
    private var cache: (guides: [String: PriceGuide], fetchedAt: Date)?

    init(repository: CatalogRepository = RemoteCatalogRepository(), ttl: TimeInterval = 3600) {
        self.repository = repository
        self.ttl = ttl
    }

    func priceReport(for query: PriceQuery) async throws -> ProviderPriceReport {
        guard let slug = query.catalogSlug else { throw PricingProviderError.notFound }
        let guides = try await guides()
        guard let guide = guides[slug] else { throw PricingProviderError.notFound }
        return ProviderPriceReport(
            provider: id,
            matchedProductID: slug,
            matchedTitle: query.title,
            matchedPlatform: query.platform,
            points: guide.points,
            salesVolumeYearly: guide.salesVolumeYearly,
            retrievedAt: guide.asOf
        )
    }

    private func guides() async throws -> [String: PriceGuide] {
        if let cache, Date().timeIntervalSince(cache.fetchedAt) < ttl {
            return cache.guides
        }
        do {
            let feed = try await repository.fetchPriceGuides()
            cache = (feed.guides, Date())
            return feed.guides
        } catch {
            if let cache { return cache.guides }   // stale beats nothing
            throw PricingProviderError.transport(String(describing: error))
        }
    }
}
