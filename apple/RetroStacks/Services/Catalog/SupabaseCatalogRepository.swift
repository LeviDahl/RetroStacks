import Foundation
import os

/// Fetches the reference catalog from Supabase's `catalog_items` table
/// instead of the static feed — Phase 3 of the plan in `supabase/schema.sql`
/// ("Phase 2", the table itself) / `FEATURES.md`'s "Catalog goes live in
/// Supabase". `reconcile` (`CatalogSyncService`) is untouched: this is a
/// drop-in `CatalogRepository`, same contract, different origin.
///
/// Platforms stay bundled/local-only (see the schema's own note on why —
/// still the small, stable, ~19-row set) — this reads them from the same
/// bundled seed `CatalogSeedStore` already uses, so `reconcile`'s platform
/// handling keeps working unchanged. Only `items` actually comes from
/// Supabase.
///
/// Auth is optional, not required: signed out, requests go through with the
/// app's own anon/publishable key, and RLS's `owner_user_id is null` clause
/// still returns every public row — the catalog has to stay fully browsable
/// signed out, same as everything else in the app. Signed in, the user's own
/// access token additionally pulls back their own private rows alongside the
/// public ones, in the exact same fetch.
///
/// Price guides are unrelated to this migration and stay on the static feed —
/// delegates to a plain `RemoteCatalogRepository` for that one method.
nonisolated struct SupabaseCatalogRepository: CatalogRepository {
    var session: URLSession = .shared
    private let priceGuides = RemoteCatalogRepository()

    /// PostgREST caps a single response at 1,000 rows regardless of `limit`;
    /// paging through `catalog_items` (~22,000 rows today, growing as users
    /// add their own) needs real pagination, not one big request.
    private static let pageSize = 1000

    func fetchCatalog(forceReload: Bool) async throws -> CatalogFeed {
        let seed = try CatalogSeedStore.bundledCatalog()
        let platforms = seed.platforms.map {
            FeedPlatform(
                slug: $0.slug, name: $0.name, shortName: $0.shortName,
                manufacturer: $0.manufacturer, generation: $0.generation,
                releaseYearNA: $0.releaseYearNA, discontinuedYearNA: $0.discontinuedYearNA,
                summary: $0.summary, iconSystemName: $0.iconSystemName, regions: $0.regions ?? []
            )
        }
        let items = try await fetchAllItems()
        return CatalogFeed(version: "supabase", generatedAt: .now, platforms: platforms, items: items)
    }

    func fetchPriceGuides(forceReload: Bool) async throws -> PriceGuideFeed {
        try await priceGuides.fetchPriceGuides(forceReload: forceReload)
    }

    // MARK: - Paginated fetch

    private func fetchAllItems() async throws -> [FeedItem] {
        let token = (try? await AccountService.shared.validAccessToken()) ?? SupabaseConfig.anonKey

        var all: [FeedItem] = []
        var offset = 0
        while true {
            let page = try await fetchPage(accessToken: token, offset: offset, limit: Self.pageSize)
            all.append(contentsOf: page)
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        return all
    }

    private func fetchPage(accessToken: String, offset: Int, limit: Int) async throws -> [FeedItem] {
        guard var components = URLComponents(
            url: SupabaseConfig.restURL.appending(path: "catalog_items"),
            resolvingAgainstBaseURL: false
        ) else {
            throw CatalogError.transport("couldn't build request URL for catalog_items")
        }
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "order", value: "slug"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components.url else {
            throw CatalogError.transport("couldn't build request URL for catalog_items")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AppLog.network.error("SupabaseCatalogRepository: transport error — \(error.localizedDescription, privacy: .public)")
            throw CatalogError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLog.network.error("SupabaseCatalogRepository: HTTP \(status, privacy: .public)")
            throw CatalogError.badStatus(status)
        }
        do {
            let rows = try JSONDecoder.exactKeys.decode([SupabaseCatalogItemRow].self, from: data)
            return rows.map(\.asFeedItem)
        } catch {
            AppLog.network.error("SupabaseCatalogRepository: decode failed — \(String(describing: error), privacy: .public)")
            throw CatalogError.decoding(String(describing: error))
        }
    }
}

/// Wire row for `public.catalog_items` — explicit `CodingKeys`, same reasoning
/// as `SupabaseCollectionRow`: never paired with `.convertFromSnakeCase`.
nonisolated struct SupabaseCatalogItemRow: Decodable, Sendable {
    var slug: String
    var platformSlug: String
    var kind: String
    var name: String
    var variant: String?
    var releaseYearNA: Int?
    var regions: [String]?
    var manufacturerOrPublisher: String?
    var developer: String?
    var genre: String?
    var upc: String?
    var summary: String?
    var imageURLString: String?
    var imageCredit: String?
    var imageLicense: String?
    /// `nil` for a public row; set to the owning account's id for a private,
    /// user-created row. See `CatalogItem.ownerUserID`.
    var ownerUserID: UUID?

    enum CodingKeys: String, CodingKey {
        case slug
        case platformSlug = "platform_slug"
        case kind, name, variant
        case releaseYearNA = "release_year_na"
        case regions
        case manufacturerOrPublisher = "manufacturer_or_publisher"
        case developer, genre, upc, summary
        case imageURLString = "image_url_string"
        case imageCredit = "image_credit"
        case imageLicense = "image_license"
        case ownerUserID = "owner_user_id"
    }

    var asFeedItem: FeedItem {
        FeedItem(
            slug: slug, platformSlug: platformSlug, kind: kind, name: name, variant: variant,
            releaseYearNA: releaseYearNA, regions: regions, manufacturerOrPublisher: manufacturerOrPublisher,
            developer: developer, genre: genre, upc: upc, summary: summary,
            imageURL: imageURLString, imageCredit: imageCredit, imageLicense: imageLicense,
            ownerUserID: ownerUserID
        )
    }
}
