import Foundation
import os

/// Admin-only public-catalog curation — excluding bootlegs/ROM-hacks/etc.
/// from the shared catalog for *every* user, not just locally (see
/// `CatalogItem.isHidden` for the local-only equivalent). Calls the
/// `admin_exclude_catalog_items` / `admin_restore_catalog_items` / `is_admin`
/// RPCs added in `supabase/schema.sql`'s Phase 5 section — those functions
/// are the real security boundary (checked against the `admins` table
/// server-side, which the client can't read directly); this type is a thin,
/// unprivileged wire client around them, same shape as
/// `CustomCatalogItemService`.
nonisolated struct AdminCatalogCurationService {
    var session: URLSession = .shared

    /// Whether the signed-in user is an admin. `false` (never thrown) for
    /// signed-out or any error — this only ever gates optional UI, not a
    /// security boundary itself (the RPCs enforce that server-side
    /// regardless), so failing closed to "not admin" is the right default.
    func checkIsAdmin() async -> Bool {
        do {
            let token = try await AccountService.shared.validAccessToken()
            let data = try await rpc("is_admin", body: [:], accessToken: token)
            return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
        } catch {
            return false
        }
    }

    /// Excludes the given public catalog slugs for every user (soft delete —
    /// see the schema comment). Throws `SyncError.notSignedIn` signed out,
    /// or the server's own "not authorized" if the caller isn't an admin.
    func exclude(slugs: [String]) async throws {
        try await callBulk("admin_exclude_catalog_items", slugs: slugs)
    }

    /// Reverses `exclude(slugs:)` — clears the tombstone.
    func restore(slugs: [String]) async throws {
        try await callBulk("admin_restore_catalog_items", slugs: slugs)
    }

    private func callBulk(_ function: String, slugs: [String]) async throws {
        guard !slugs.isEmpty else { return }
        let token = try await AccountService.shared.validAccessToken()
        _ = try await rpc(function, body: ["slugs": slugs], accessToken: token)
    }

    private func rpc(_ function: String, body: [String: Any], accessToken: String) async throws -> Data {
        let url = SupabaseConfig.restURL.appending(path: "rpc/\(function)")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw CatalogError.decoding("couldn't encode \(function) request body: \(error)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AppLog.network.error(
                "AdminCatalogCurationService.\(function, privacy: .public): transport error — \(error.localizedDescription, privacy: .public)"
            )
            throw CatalogError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? "status \(status)"
            AppLog.network.error(
                "AdminCatalogCurationService.\(function, privacy: .public): HTTP \(status, privacy: .public) — \(message, privacy: .public)"
            )
            throw CatalogError.badStatus(status)
        }
        return data
    }
}
