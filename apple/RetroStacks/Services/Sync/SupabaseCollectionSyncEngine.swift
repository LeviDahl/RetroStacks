import Foundation

/// Wire row for `public.collection_items` (see `supabase/schema.sql`) — plain
/// PostgREST over REST, no SDK. `keyEncodingStrategy/.convertToSnakeCase` on
/// `JSONEncoder.supabase` maps these camelCase names to the DB's snake_case
/// columns automatically.
nonisolated private struct SupabaseCollectionRow: Codable {
    var id: UUID
    var userID: UUID
    var catalogSlug: String?
    var status: String
    var condition: String?
    var completeness: String?
    var hasBox: Bool
    var hasManual: Bool
    var hasInserts: Bool
    var hasOriginalPackaging: Bool
    var gradingCompany: String
    var gradeScore: Double?
    var pricePaid: Decimal?
    var dateAcquired: Date?
    var acquisitionSource: String?
    var estimatedValueOverride: Decimal?
    var storageLocation: String?
    var notes: String
    var playStatus: String?
    var dateAdded: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(change: CollectionChange, userID: UUID) {
        let entry = change.payload
        self.id = change.exportID
        self.userID = userID
        self.catalogSlug = entry?.catalogSlug
        self.status = entry?.status ?? CollectionStatus.owned.rawValue
        self.condition = entry?.condition
        self.completeness = entry?.completeness
        self.hasBox = entry?.hasBox ?? false
        self.hasManual = entry?.hasManual ?? false
        self.hasInserts = entry?.hasInserts ?? false
        self.hasOriginalPackaging = entry?.hasOriginalPackaging ?? false
        self.gradingCompany = entry?.gradingCompany ?? GradingCompany.none.rawValue
        self.gradeScore = entry?.gradeScore
        self.pricePaid = entry?.pricePaid
        self.dateAcquired = entry?.dateAcquired
        self.acquisitionSource = entry?.acquisitionSource
        self.estimatedValueOverride = entry?.estimatedValueOverride
        self.storageLocation = entry?.storageLocation
        self.notes = entry?.notes ?? ""
        self.playStatus = entry?.playStatus
        self.dateAdded = entry?.dateAdded ?? change.updatedAt
        self.updatedAt = change.updatedAt
        self.deletedAt = change.deletedAt
    }

    var asChange: CollectionChange {
        CollectionChange(
            exportID: id,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            payload: CollectionArchive.Entry(
                exportID: id,
                catalogSlug: catalogSlug,
                catalogName: nil,
                platformShortName: nil,
                status: status,
                condition: condition,
                completeness: completeness,
                hasBox: hasBox,
                hasManual: hasManual,
                hasInserts: hasInserts,
                hasOriginalPackaging: hasOriginalPackaging,
                gradingCompany: gradingCompany,
                gradeScore: gradeScore,
                pricePaid: pricePaid,
                dateAcquired: dateAcquired,
                acquisitionSource: acquisitionSource,
                estimatedValueOverride: estimatedValueOverride,
                storageLocation: storageLocation,
                notes: notes,
                playStatus: playStatus,
                dateAdded: dateAdded,
                updatedAt: updatedAt,
                photosBase64: []
            )
        )
    }
}

/// `CollectionSyncEngine` over Supabase's PostgREST, matching `supabase/schema.sql`.
/// Reads the bearer token from `AccountService` on every call (`await`-ing across
/// the actor boundary is fine here — see `AccountService.validAccessToken()`),
/// so this type itself stays `nonisolated`/`Sendable` and can run off the main
/// actor like the rest of the sync pipeline.
///
/// Photos are **not** synced yet (`CollectionItem.photoData` stays local-only
/// here) — `supabase/README.md` calls for a Storage-bucket upload, left for a
/// follow-up so this pass could actually be exercised end-to-end.
nonisolated struct SupabaseCollectionSyncEngine: CollectionSyncEngine {
    var isEnabled: Bool { true }
    var session: URLSession = .shared

    func pull(since date: Date?) async throws -> [CollectionChange] {
        let token = try await AccountService.shared.validAccessToken()
        guard let userID = await AccountService.shared.currentUserID else {
            throw SyncError.notSignedIn
        }

        var query = [URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")]
        query.append(URLQueryItem(name: "order", value: "updated_at.asc"))
        if let date {
            let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
            query.append(URLQueryItem(name: "updated_at", value: "gt.\(iso)"))
        }

        let data = try await request(path: "collection_items", method: "GET", query: query, accessToken: token)
        do {
            let rows = try JSONDecoder.supabase.decode([SupabaseCollectionRow].self, from: data)
            return rows.map(\.asChange)
        } catch {
            throw SyncError.transport("bad response: \(error)")
        }
    }

    func push(_ changes: [CollectionChange]) async throws -> [CollectionChange] {
        guard !changes.isEmpty else { return [] }
        let token = try await AccountService.shared.validAccessToken()
        guard let userID = await AccountService.shared.currentUserID else {
            throw SyncError.notSignedIn
        }

        let rows = changes.map { SupabaseCollectionRow(change: $0, userID: userID) }
        let body: Data
        do {
            body = try JSONEncoder.supabase.encode(rows)
        } catch {
            throw SyncError.transport("couldn't encode changes: \(error)")
        }

        let data = try await request(
            path: "collection_items",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            accessToken: token,
            body: body,
            prefer: "resolution=merge-duplicates,return=representation"
        )
        do {
            let responseRows = try JSONDecoder.supabase.decode([SupabaseCollectionRow].self, from: data)
            return responseRows.map(\.asChange)
        } catch {
            throw SyncError.transport("bad response: \(error)")
        }
    }

    // MARK: - Wire helper

    private func request(
        path: String,
        method: String,
        query: [URLQueryItem],
        accessToken: String,
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: SupabaseConfig.restURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query

        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.transport("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw SyncError.transport(message)
        }
        return data
    }
}
