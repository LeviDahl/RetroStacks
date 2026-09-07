import Foundation

nonisolated protocol CatalogRepository: Sendable {
    func fetchCatalog() async throws -> CatalogFeed
    func fetchPriceGuides() async throws -> PriceGuideFeed
}

nonisolated enum CatalogError: Error, CustomStringConvertible {
    case badStatus(Int)
    case transport(String)
    case decoding(String)

    var description: String {
        switch self {
        case .badStatus(let code): "server returned \(code)"
        case .transport(let m): "network error: \(m)"
        case .decoding(let m): "bad data: \(m)"
        }
    }
}

/// Fetches the static feed. Relies on `URLCache` + the CDN's `ETag` /
/// `Last-Modified` so repeat calls are cheap and it works offline once warm.
nonisolated struct RemoteCatalogRepository: CatalogRepository {
    var session: URLSession = .shared

    func fetchCatalog() async throws -> CatalogFeed {
        try await get(BackendConfig.catalogURL)
    }

    func fetchPriceGuides() async throws -> PriceGuideFeed {
        try await get(BackendConfig.priceGuideURL)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CatalogError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder.retroStacksFeed.decode(T.self, from: data)
        } catch {
            throw CatalogError.decoding(String(describing: error))
        }
    }
}
