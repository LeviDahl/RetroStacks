import Foundation
import os

/// Write path for a private, user-owned `catalog_items` row — a new variant
/// (5-screw NES, black label, …), a bootleg, or a game the shared catalog is
/// missing (see `supabase/schema.sql`'s Phase 2 section and
/// `CatalogItem.ownerUserID`). Sibling to `SupabaseCollectionSyncEngine`, same
/// auth-header pattern, but a single plain `INSERT` rather than an offline
/// change-tracking queue: creating a custom entry is a rare, explicit action,
/// not something that changes continuously like the collection does.
///
/// Requires the user be signed in — RLS's `catalog_items_insert_own` policy
/// only ever accepts `owner_user_id = auth.uid()`, never an anon write — so
/// `create` throws `SyncError.notSignedIn` up front rather than letting the
/// request round-trip just to get a 401.
nonisolated struct CustomCatalogItemService {
    var session: URLSession = .shared

    struct Draft {
        var platformSlug: String
        var kind: ItemKind
        var name: String
        var variant: String?
        var releaseYearNA: Int?
        var manufacturerOrPublisher: String?
        var developer: String?
        var genre: String?
        var upc: String?
        var summary: String?
    }

    /// Inserts the row remotely and hands back the `FeedItem` Supabase
    /// actually stored (slug, `owner_user_id`, everything) — callers write
    /// that straight into SwiftData rather than re-deriving it from the draft.
    func create(_ draft: Draft) async throws -> FeedItem {
        let token = try await AccountService.shared.validAccessToken()
        guard let userID = await AccountService.shared.currentUserID else {
            throw SyncError.notSignedIn
        }

        let request = try makeRequest(for: NewCatalogItemRow(draft: draft, ownerUserID: userID), accessToken: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AppLog.network.error("CustomCatalogItemService.create: transport error — \(error.localizedDescription, privacy: .public)")
            throw CatalogError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? "status \(status)"
            AppLog.network.error("CustomCatalogItemService.create: HTTP \(status, privacy: .public) — \(message, privacy: .public)")
            throw CatalogError.badStatus(status)
        }
        return try decodeCreated(from: data)
    }

    private func makeRequest(for row: NewCatalogItemRow, accessToken: String) throws -> URLRequest {
        let body: Data
        do {
            body = try JSONEncoder.exactKeys.encode(row)
        } catch {
            throw CatalogError.decoding("couldn't encode new catalog item: \(error)")
        }

        guard var components = URLComponents(
            url: SupabaseConfig.restURL.appending(path: "catalog_items"),
            resolvingAgainstBaseURL: false
        ) else {
            throw CatalogError.transport("couldn't build request URL for catalog_items")
        }
        components.queryItems = [URLQueryItem(name: "select", value: "*")]
        guard let url = components.url else {
            throw CatalogError.transport("couldn't build request URL for catalog_items")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = body
        return request
    }

    private func decodeCreated(from data: Data) throws -> FeedItem {
        do {
            let rows = try JSONDecoder.exactKeys.decode([SupabaseCatalogItemRow].self, from: data)
            guard let created = rows.first else {
                throw CatalogError.decoding("empty response inserting catalog item")
            }
            return created.asFeedItem
        } catch let error as CatalogError {
            throw error
        } catch {
            AppLog.network.error("CustomCatalogItemService.create: decode failed — \(String(describing: error), privacy: .public)")
            throw CatalogError.decoding(String(describing: error))
        }
    }

    // MARK: - Slug

    /// Private slugs only need to be unique per-owner (the schema's
    /// `catalog_items_private_slug_idx` is on `(slug, owner_user_id)`), so a
    /// short random suffix on a human-readable base is enough to avoid a
    /// collision without a round-trip existence check first.
    static func makeSlug(platformSlug: String, name: String, variant: String?) -> String {
        var parts = [platformSlug, name]
        if let variant, !variant.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(variant) }
        let base = parts.map(slugify).filter { !$0.isEmpty }.joined(separator: "-")
        let suffix = UUID().uuidString.prefix(6).lowercased()
        return base.isEmpty ? "custom-\(suffix)" : "\(base)-\(suffix)"
    }

    private static func slugify(_ s: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in s.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// Wire row for inserting one new `catalog_items` record. Explicit
/// `CodingKeys`, same reasoning as `SupabaseCatalogItemRow` /
/// `SupabaseCollectionRow` — never paired with a key-conversion strategy.
/// Plain synthesized `Encodable` is fine here (unlike `SupabaseCollectionRow`,
/// which has to hand-write `encode(to:)`): that struct's problem only bites
/// when encoding an *array* for a bulk push, where every object needs the
/// same key set — this is always a single-object POST.
nonisolated private struct NewCatalogItemRow: Encodable {
    var slug: String
    var ownerUserID: UUID
    var platformSlug: String
    var kind: String
    var name: String
    var variant: String?
    var releaseYearNA: Int?
    var manufacturerOrPublisher: String?
    var developer: String?
    var genre: String?
    var upc: String?
    var summary: String

    enum CodingKeys: String, CodingKey {
        case slug
        case ownerUserID = "owner_user_id"
        case platformSlug = "platform_slug"
        case kind, name, variant
        case releaseYearNA = "release_year_na"
        case manufacturerOrPublisher = "manufacturer_or_publisher"
        case developer, genre, upc, summary
    }

    init(draft: CustomCatalogItemService.Draft, ownerUserID: UUID) {
        self.slug = CustomCatalogItemService.makeSlug(
            platformSlug: draft.platformSlug, name: draft.name, variant: draft.variant
        )
        self.ownerUserID = ownerUserID
        self.platformSlug = draft.platformSlug
        self.kind = draft.kind.rawValue
        self.name = draft.name
        self.variant = draft.variant
        self.releaseYearNA = draft.releaseYearNA
        self.manufacturerOrPublisher = draft.manufacturerOrPublisher
        self.developer = draft.developer
        self.genre = draft.genre
        self.upc = draft.upc
        self.summary = draft.summary ?? ""
    }
}
