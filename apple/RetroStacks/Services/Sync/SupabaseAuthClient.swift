import Foundation
import os

nonisolated enum SupabaseAuthError: Error, CustomStringConvertible {
    case badStatus(Int, String?)
    case transport(String)
    case decoding(String)
    case noPastedLink

    var description: String {
        switch self {
        case .badStatus(let code, let message): "\(message ?? "request failed") (\(code))"
        case .transport(let m): "network error: \(m)"
        case .decoding(let m): "bad response: \(m)"
        case .noPastedLink: "couldn't find a sign-in link in that text"
        }
    }

    /// Plain-language version for UI (sign-in sheet, status badge).
    var userMessage: String {
        switch self {
        case .badStatus(_, let message): message ?? "The sign-in server rejected that."
        case .transport: "Couldn’t reach the sign-in server."
        case .decoding: "The sign-in server sent back something unexpected."
        case .noPastedLink: "That doesn’t look like the sign-in link from the email — paste the whole link."
        }
    }
}

/// Raw GoTrue token response shape (`/otp` verify, `/token?grant_type=refresh_token`).
nonisolated private struct GoTrueTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var user: GoTrueUser
}

nonisolated private struct GoTrueUser: Decodable {
    var id: UUID
    var email: String?
}

nonisolated private struct GoTrueErrorBody: Decodable {
    var msg: String?
    var message: String?
    var errorDescription: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case msg, message, error
        case errorDescription = "error_description"
    }

    var text: String? { msg ?? message ?? errorDescription ?? error }
}

/// GoTrue (Supabase Auth) over plain REST — no SDK, per `supabase/README.md`.
/// Email-only, magic-link: send a link, the user pastes it back (no custom
/// URL scheme needed, so no Xcode target changes are required to ship this).
nonisolated struct SupabaseAuthClient: Sendable {
    var session: URLSession = .shared

    /// Kicks off the email. `create_user: true` so a first-time email also
    /// works as sign-up — this app has no separate "create an account" step.
    func sendMagicLink(to email: String) async throws {
        _ = try await send(
            path: "otp",
            body: ["email": email, "create_user": true]
        )
    }

    /// The user copies the sign-in link from their email (without opening it)
    /// and pastes it in. GoTrue's link is its own verify endpoint with `token`
    /// (or, on newer projects, `token_hash`) and `type` query params — this
    /// extracts those and calls `/verify` directly, so nothing ever has to
    /// open the link in a browser or catch a deep-link callback.
    func completeSignIn(pastedLink: String, email: String) async throws -> SupabaseSession {
        guard let (token, type) = Self.extractToken(from: pastedLink) else {
            throw SupabaseAuthError.noPastedLink
        }
        let data = try await send(
            path: "verify",
            body: ["type": type, "token": token, "email": email]
        )
        return try Self.session(from: data)
    }

    func refresh(_ refreshToken: String) async throws -> SupabaseSession {
        let data = try await send(
            path: "token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken]
        )
        return try Self.session(from: data)
    }

    /// Best-effort — the client-side sign-out (clearing the keychain) is what
    /// actually matters; this just invalidates the refresh token server-side.
    func signOut(accessToken: String) async {
        _ = try? await send(path: "logout", accessToken: accessToken, body: [:])
    }

    // MARK: - Wire helpers

    private static func session(from data: Data) throws -> SupabaseSession {
        let decoded: GoTrueTokenResponse
        do {
            decoded = try JSONDecoder.supabase.decode(GoTrueTokenResponse.self, from: data)
        } catch {
            throw SupabaseAuthError.decoding(String(describing: error))
        }
        return SupabaseSession(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(decoded.expiresIn)),
            userID: decoded.user.id,
            email: decoded.user.email
        )
    }

    /// Accepts either `token=` or `token_hash=` (GoTrue has used both names
    /// across versions) and `type=` (defaults to `magiclink`, GoTrue's default
    /// for `/otp` without `type: "signup"`).
    static func extractToken(from pastedText: String) -> (token: String, type: String)? {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let items = components.queryItems else { return nil }
        let byName = Dictionary(items.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        guard let token = (byName["token"] ?? byName["token_hash"]) ?? nil, !token.isEmpty else {
            return nil
        }
        let type = (byName["type"] ?? nil) ?? "magiclink"
        return (token, type)
    }

    private func send(
        path: String,
        query: [URLQueryItem] = [],
        accessToken: String? = nil,
        body: [String: Any]
    ) async throws -> Data {
        var components = URLComponents(url: SupabaseConfig.authURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AppLog.network.error("SupabaseAuthClient \(path): transport error — \(error.localizedDescription)")
            throw SupabaseAuthError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            AppLog.network.error("SupabaseAuthClient \(path): no HTTP response")
            throw SupabaseAuthError.transport("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GoTrueErrorBody.self, from: data))?.text
            AppLog.auth.error("SupabaseAuthClient \(path): HTTP \(http.statusCode) — \(message ?? "no message")")
            throw SupabaseAuthError.badStatus(http.statusCode, message)
        }
        return data
    }
}
