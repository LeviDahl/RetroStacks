import Foundation
import Observation

/// Account / auth state, backed by Supabase Auth (GoTrue) over plain REST —
/// see `SupabaseAuthClient`. The app is **local-first**: everything works
/// while `state == .signedOut`; signing in only adds multi-device sync.
///
/// Sign-in is email magic-link with no custom URL scheme: the user pastes the
/// link back into the app (`completeSignIn(pastedLink:)`) rather than the app
/// catching a deep-link callback — that needs no Xcode target changes to ship.
@MainActor
@Observable
final class AccountService {
    enum State: Equatable {
        case signedOut
        case sendingLink
        case awaitingLink(email: String)
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

    static let shared = AccountService()

    private let auth: SupabaseAuthClient
    private let store: SupabaseSessionStore
    private var pendingEmail: String?

    init(auth: SupabaseAuthClient = SupabaseAuthClient(), store: SupabaseSessionStore = .shared) {
        self.auth = auth
        self.store = store
        // Keychain I/O deliberately NOT done inline here: `DashboardView` reads
        // `AccountService.shared` from a `@State` initializer, which runs
        // synchronously during that view's first render. A blocking
        // `SecItemCopyMatching` call in `init()` delayed the window appearing
        // at all under XCUITest hosting on macOS (found 2026-09-13 debugging
        // 4 UI test failures whose accessibility-hierarchy dumps showed no
        // app window ever rendered — only the menu bar). Deferring to a Task
        // lets `init()` return immediately; `state` updates a moment later.
        Task { await self.restoreSession() }
    }

    private func restoreSession() async {
        if let session = store.load() {
            state = .signedIn(userID: session.userID.uuidString, email: session.email)
        }
    }

    var summary: String {
        switch state {
        case .signedOut: "Local only — not signed in"
        case .sendingLink: "Sending sign-in link…"
        case .awaitingLink(let email): "Check \(email) for a sign-in link"
        case .signedIn(_, let email): "Signed in as \(email ?? "your account")"
        }
    }

    func sendMagicLink(to email: String) async throws {
        state = .sendingLink
        do {
            try await auth.sendMagicLink(to: email)
            pendingEmail = email
            state = .awaitingLink(email: email)
        } catch {
            state = .signedOut
            throw error
        }
    }

    /// The user pastes the link they received. No `email` param needed here —
    /// it's the one `sendMagicLink` just sent to.
    func completeSignIn(pastedLink: String) async throws {
        guard let email = pendingEmail else { throw AccountError.notConfigured }
        let session = try await auth.completeSignIn(pastedLink: pastedLink, email: email)
        store.save(session)
        pendingEmail = nil
        state = .signedIn(userID: session.userID.uuidString, email: session.email)
        AppStatusCenter.shared.clear(.account)
    }

    func cancelSignIn() {
        pendingEmail = nil
        state = .signedOut
    }

    func signOut() {
        if let session = store.load() {
            Task { await auth.signOut(accessToken: session.accessToken) }
        }
        store.clear()
        state = .signedOut
    }

    /// The bearer token for authenticated REST calls (`SupabaseCollectionSyncEngine`),
    /// refreshing first if it's near expiry. Throws `.notSignedIn` when signed out.
    func validAccessToken() async throws -> String {
        guard var session = store.load() else { throw AccountError.notSignedIn }
        if session.needsRefresh {
            do {
                session = try await auth.refresh(session.refreshToken)
                store.save(session)
                state = .signedIn(userID: session.userID.uuidString, email: session.email)
            } catch {
                // Refresh token itself is dead — the user has to sign in again.
                store.clear()
                state = .signedOut
                throw AccountError.notSignedIn
            }
        }
        return session.accessToken
    }

    var currentUserID: UUID? { store.load()?.userID }
}

nonisolated enum AccountError: Error, CustomStringConvertible {
    case notConfigured
    case notSignedIn
    case network(String)

    var description: String {
        switch self {
        case .notConfigured: "Sign-in isn't set up yet."
        case .notSignedIn: "Not signed in."
        case .network(let m): "Network error: \(m)"
        }
    }
}
