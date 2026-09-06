import Foundation

// Placeholder adapters. They conform to `PricingProvider` and document the
// mapping seam, but report `isConfigured == false` so `PricingService` skips
// them until someone implements the fetch. Add real ones the same way and drop
// them into `PricingService.makeDefault()` in priority order.

/// **eBay Browse API** — `buy/browse/v1/item_summary/search`.
/// Mapping intent:
/// - cheapest active listing → `PricePoint(kind: .listingLow)`
/// - with Marketplace Insights access, median sold → `.soldMedian`
/// Needs an OAuth client-credentials token. Good redundancy for common items;
/// weaker for rare/graded pieces with thin listings.
nonisolated struct EbayBrowseProvider: PricingProvider {
    let id: PricingProviderID = .ebay
    var isConfigured: Bool { false }

    func priceReport(for query: PriceQuery) async throws -> ProviderPriceReport {
        throw PricingProviderError.notConfigured
    }
}

/// **GG.deals** — digital storefront price aggregation.
/// Mapping intent: current lowest official / keyshop price → `.listingLow`
/// against `MarketCondition.new`. Most useful for modern & PC titles; retro
/// cartridges are out of scope for this source.
nonisolated struct GGDealsProvider: PricingProvider {
    let id: PricingProviderID = .ggDeals
    var isConfigured: Bool { false }

    func priceReport(for query: PriceQuery) async throws -> ProviderPriceReport {
        throw PricingProviderError.notConfigured
    }
}
