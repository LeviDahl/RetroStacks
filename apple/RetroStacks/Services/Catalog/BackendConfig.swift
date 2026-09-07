import Foundation

/// Where the app reads reference data from.
///
/// The `/v1/*.json` contract (see `CatalogFeed.swift` + `PricingModels.swift`) is
/// the only interface — it doesn't matter whether the origin is static files on
/// GitHub Pages, a PHP/MySQL app, or Supabase's PostgREST. Switching origins is
/// just changing `feedBaseURL`; the app is otherwise unaware.
///
/// `data.retrostacks.com` is a GitHub Pages custom domain (`CNAME` at GoDaddy →
/// `levidahl.github.io`); the raw `https://levidahl.github.io/RetroStacks` still
/// works and 301s here.
nonisolated enum BackendConfig {
    static let feedBaseURL = URL(string: "https://data.retrostacks.com")!

    static var catalogURL: URL { feedBaseURL.appending(path: "v1/catalog.json") }
    static var priceGuideURL: URL { feedBaseURL.appending(path: "v1/price-guide.json") }
    static var metaURL: URL { feedBaseURL.appending(path: "v1/meta.json") }
}
