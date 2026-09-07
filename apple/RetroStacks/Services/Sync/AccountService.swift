import Foundation
import Observation

/// Account / auth state. The app is **local-first**: everything works while
/// `state == .signedOut`, which is the only state today. A Supabase-backed
/// implementation swaps in behind the same surface later (email magic-link —
/// no Apple Developer account needed).
@MainActor
@Observable
final class AccountService {
    enum State: Equatable {
        case signedOut
        case signedIn(userID: String, email: String?)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
        var userID: String? {
            if case .signedIn(let id, _) = self { return id }
            return nil
        }
    }

    private(set) var state: State = .signedOut

    /// Swap for `SupabaseAccountService()` (or similar) in Phase 1.
    static let shared = AccountService()

    var summary: String {
        switch state {
        case .signedOut:
            "Local only — not signed in"
        case .signedIn(_, let email):
            "Signed in as \(email ?? "your account")"
        }
    }

    func sendMagicLink(to email: String) async throws {
        throw AccountError.notConfigured
    }

    func signOut() {
        state = .signedOut
    }
}

nonisolated enum AccountError: Error, CustomStringConvertible {
    case notConfigured
    case network(String)

    var description: String {
        switch self {
        case .notConfigured: "Sign-in isn't set up yet."
        case .network(let m): "Network error: \(m)"
        }
    }
}
