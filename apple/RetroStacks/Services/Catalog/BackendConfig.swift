import Foundation

/// Where the app reads reference data from.
///
/// The `/v1/*.json` contract (see `CatalogFeed.swift` + `PricingModels.swift`) is
/// the only interface — it doesn't matter whether the origin is static files on
/// GitHub Pages, a PHP/MySQL app, or Supabase's PostgREST. Switching origins is
/// just changing `feedBaseURL`; the app is otherwise unaware.
///
/// TODO: once `data.retrostacks.com` resolves (GoDaddy `CNAME data → levidahl.github.io`
/// + the domain set in repo Settings → Pages, or the `FEED_CNAME` repo variable),
/// change `feedBaseURL` to `https://data.retrostacks.com`. Until then it points at
/// the raw Pages URL, which already works.
nonisolated enum BackendConfig {
    static let feedBaseURL = URL(string: "https://levidahl.github.io/RetroStacks")!

    static var catalogURL: URL { feedBaseURL.appending(path: "v1/catalog.json") }
    static var priceGuideURL: URL { feedBaseURL.appending(path: "v1/price-guide.json") }
    static var metaURL: URL { feedBaseURL.appending(path: "v1/meta.json") }
}
