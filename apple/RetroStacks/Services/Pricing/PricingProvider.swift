import Foundation

/// A pricing source. Each concrete adapter maps one external service's API onto
/// the canonical `PricePoint` / `ProviderPriceReport` schema. Keep adapters
/// *lite*: fetch, map, return — no caching, no cross-provider logic (that's
/// `PricingService`'s job).
///
/// Adapters are value types and `Sendable`; `priceReport(for:)` runs off the
/// main actor.
nonisolated protocol PricingProvider: Sendable {
    var id: PricingProviderID { get }
    var displayName: String { get }

    /// Usable right now? e.g. an API token is configured. Unconfigured providers
    /// are skipped by the aggregator rather than throwing.
    var isConfigured: Bool { get }

    func priceReport(for query: PriceQuery) async throws -> ProviderPriceReport
}

nonisolated extension PricingProvider {
    var displayName: String { id.displayName }
}

nonisolated enum PricingProviderError: Error, Sendable, CustomStringConvertible {
    case notConfigured
    case notFound
    case rateLimited
    case transport(String)
    case decoding(String)
    case upstream(status: Int, message: String?)

    var description: String {
        switch self {
        case .notConfigured: "provider not configured"
        case .notFound: "no matching product"
        case .rateLimited: "rate limited"
        case .transport(let m): "transport error: \(m)"
        case .decoding(let m): "decoding error: \(m)"
        case .upstream(let status, let m): "upstream \(status): \(m ?? "—")"
        }
    }
}
