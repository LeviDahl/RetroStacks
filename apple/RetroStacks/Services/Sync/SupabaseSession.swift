import Foundation
import Security

/// A GoTrue (Supabase Auth) session — just enough to authorize REST calls and
/// know who's signed in. Kept deliberately separate from `AccountService`
/// (`@MainActor`, UI-facing) so `SupabaseCollectionSyncEngine` can read the
/// current token without hopping actors: this type and its store are
/// `nonisolated`/`Sendable`, safe to touch from a background sync task.
nonisolated struct SupabaseSession: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
    var email: String?

    var isExpired: Bool { expiresAt <= .now }
    /// Refresh a little before the server actually cuts it off, so a slow
    /// request doesn't race the expiry.
    var needsRefresh: Bool { expiresAt <= Date.now.addingTimeInterval(60) }
}

/// Keychain-backed persistence for the one session this device holds. No
/// third-party dependency — GenericPassword item, `kSecAttrAccessible` scoped
/// to "this device, after first unlock," which is the right tradeoff for a
/// token that should survive a restart but not migrate in a backup meant for
/// another device.
nonisolated final class SupabaseSessionStore: Sendable {
    static let shared = SupabaseSessionStore()
    private init() {}

    private let service = "com.levidahlstrom.RetroStacks.supabase"
    private let account = "session"

    func load() -> SupabaseSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder.supabase.decode(SupabaseSession.self, from: data)
    }

    func save(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder.supabase.encode(session) else { return }
        var query = baseQuery
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension JSONEncoder {
    nonisolated static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
