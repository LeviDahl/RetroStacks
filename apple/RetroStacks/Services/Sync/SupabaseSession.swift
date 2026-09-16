import Foundation
import Security
import os

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
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                AppLog.sync.error("SupabaseSessionStore.load: SecItemCopyMatching failed, status \(status, privacy: .public)")
            }
            return nil
        }
        guard let data = item as? Data else {
            AppLog.sync.error("SupabaseSessionStore.load: keychain item had no data")
            return nil
        }
        do {
            return try JSONDecoder.exactKeys.decode(SupabaseSession.self, from: data)
        } catch {
            AppLog.sync.error("SupabaseSessionStore.load: decode failed — \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func save(_ session: SupabaseSession) {
        let data: Data
        do {
            data = try JSONEncoder.exactKeys.encode(session)
        } catch {
            AppLog.sync.error("SupabaseSessionStore.save: encode failed — \(String(describing: error), privacy: .public)")
            return
        }
        let query = baseQuery
        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existsStatus == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updateStatus != errSecSuccess {
                AppLog.sync.error("SupabaseSessionStore.save: SecItemUpdate failed, status \(updateStatus, privacy: .public)")
                // Found live 2026-09-16: an existing item whose ACL no longer
                // matches the current process's code signature (e.g. a
                // locally ad-hoc-signed build that gets a new signature on
                // every rebuild — no Apple Developer account here, see
                // CLAUDE.md) fails `SecItemUpdate` with `errSecAuthFailed`
                // (-25293) and *stays stuck that way forever* — every future
                // sign-in would silently fail to persist, while the caller
                // (which never checked this return value) went on to set
                // `.signedIn` anyway, leaving a real, working in-memory
                // session that vanished on the next launch and made every
                // sync call `.notSignedIn`. Recover by deleting the
                // unreadable item and adding fresh — a fresh `SecItemAdd`
                // gets a brand-new ACL bound to *this* process, so it always
                // succeeds regardless of what signed the previous one.
                addFreshItem(data: data, query: query)
            }
        } else {
            addFreshItem(data: data, query: query)
        }
    }

    private func addFreshItem(data: Data, query: [String: Any]) {
        SecItemDelete(query as CFDictionary) // best-effort; ignore status, SecItemAdd below is the real signal
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLog.sync.error("SupabaseSessionStore.save: SecItemAdd failed, status \(addStatus, privacy: .public)")
        }
    }

    func clear() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.sync.error("SupabaseSessionStore.clear: SecItemDelete failed, status \(status, privacy: .public)")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

extension JSONEncoder {
    /// For GoTrue's own wire format (auth responses) — safe to auto-convert
    /// because none of those fields are acronym-cased.
    nonisolated static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    /// For types with their own explicit `CodingKeys` (`SupabaseSession`,
    /// `SupabaseCollectionRow`) — **not** paired with `.convertToSnakeCase`.
    ///
    /// `userID` is exactly the case `.convertToSnakeCase`/`.convertFromSnakeCase`
    /// get wrong asymmetrically: encoding "userID" → "user_id" is correct
    /// (Foundation's to-snake-case groups a trailing run of capitals as one
    /// unit), but decoding "user_id" back only naively capitalizes each
    /// underscore-separated segment, producing "userId" (lowercase d) — which
    /// doesn't match the property name, so `Decodable` throws `keyNotFound`
    /// and silently disappears behind a `try?`. Found 2026-09-13: this made
    /// `SupabaseSessionStore.load()` always return nil after a successful
    /// `save()`, and would have broken `SupabaseCollectionSyncEngine.pull()`
    /// on every real server response. Explicit `CodingKeys` sidestep the
    /// asymmetry entirely — this coder must never also set a key strategy, or
    /// the two conversions fight each other.
    nonisolated static var exactKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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

    /// See `JSONEncoder.exactKeys` — the decoding half of the same pairing.
    nonisolated static var exactKeys: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
