import Foundation

nonisolated protocol CatalogRepository: Sendable {
    func fetchCatalog(forceReload: Bool) async throws -> CatalogFeed
    func fetchPriceGuides(forceReload: Bool) async throws -> PriceGuideFeed
}

extension CatalogRepository {
    func fetchCatalog() async throws -> CatalogFeed { try await fetchCatalog(forceReload: false) }
    func fetchPriceGuides() async throws -> PriceGuideFeed { try await fetchPriceGuides(forceReload: false) }
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

    /// Plain-language version for the status badge (no error dumps).
    var userMessage: String {
        switch self {
        case .badStatus(let code): "The data server returned an error (\(code))."
        case .transport: "Couldn’t reach the data server."
        case .decoding: "The update was in an unexpected format."
        }
    }
}

/// Fetches the static feed. Always **revalidates with the origin** (cheap 304 via
/// ETag when unchanged) rather than trusting `max-age`, so a fresh publish is
/// picked up on the next launch without a re-download — and `forceReload` skips
/// the cache entirely for a manual "Sync now". Falls back to the cache offline.
nonisolated struct RemoteCatalogRepository: CatalogRepository {
    var session: URLSession = .shared

    func fetchCatalog(forceReload: Bool) async throws -> CatalogFeed {
        try await get(BackendConfig.catalogURL, forceReload: forceReload)
    }

    func fetchPriceGuides(forceReload: Bool) async throws -> PriceGuideFeed {
        try await get(BackendConfig.priceGuideURL, forceReload: forceReload)
    }

    private func get<T: Decodable>(_ url: URL, forceReload: Bool) async throws -> T {
        let policy: URLRequest.CachePolicy = forceReload
            ? .reloadIgnoringLocalCacheData
            : .reloadRevalidatingCacheData
        let request = URLRequest(url: url, cachePolicy: policy, timeoutInterval: 20)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Offline / unreachable: fall back to whatever's cached.
            if !forceReload,
               let cached = URLCache.shared.cachedResponse(for: request)?.data,
               let decoded = try? JSONDecoder.retroStacksFeed.decode(T.self, from: cached) {
                return decoded
            }
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
