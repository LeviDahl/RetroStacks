import Foundation

/// Where the app reads reference data from. Today this is a static JSON feed
/// published to GitHub Pages by `.github/workflows/publish-data.yml`. Swap
/// `feedBaseURL` for `https://data.retrostacks.com` once DNS is pointed at it —
/// nothing else changes.
nonisolated enum BackendConfig {
    static let feedBaseURL = URL(string: "https://levidahl.github.io/RetroStacks")!

    static var catalogURL: URL { feedBaseURL.appending(path: "v1/catalog.json") }
    static var priceGuideURL: URL { feedBaseURL.appending(path: "v1/price-guide.json") }
    static var metaURL: URL { feedBaseURL.appending(path: "v1/meta.json") }
}
