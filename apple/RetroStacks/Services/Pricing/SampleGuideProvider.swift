import Foundation

/// The zero-dependency default provider. It echoes whatever values the app
/// already holds (`PriceQuery.fallbackPoints` — sourced from the catalog seed or
/// the last cached guide) as a provider result, so the whole pricing pipeline
/// runs and renders fully offline until a real adapter is configured.
nonisolated struct SampleGuideProvider: PricingProvider {
    let id: PricingProviderID = .sampleGuide
    var isConfigured: Bool { true }

    func priceReport(for query: PriceQuery) async throws -> ProviderPriceReport {
        guard !query.fallbackPoints.isEmpty else { throw PricingProviderError.notFound }
        return ProviderPriceReport(
            provider: id,
            matchedProductID: query.catalogSlug,
            matchedTitle: query.title,
            matchedPlatform: query.platform,
            points: query.fallbackPoints,
            salesVolumeYearly: nil,
            retrievedAt: query.fallbackPoints.map(\.observedAt).max() ?? .now
        )
    }
}
