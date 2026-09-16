import Foundation
import Testing

@testable import RetroStacks

/// `extractToken(from:)` is what turns a pasted email link into something
/// `/auth/v1/verify` accepts — it's the one piece of the sign-in flow that
/// doesn't need a live Supabase project to get right, and it's easy to get
/// subtly wrong (GoTrue has used both `token` and `token_hash` across
/// versions; a real link also carries `redirect_to` and other params that
/// must be ignored, not mistaken for the token).
struct SupabaseAuthClientTests {

    @Test func extractsTokenAndTypeFromARealisticMagicLink() {
        let link = "https://vethkqrlcacmlffuzlnx.supabase.co/auth/v1/verify?token=pkce_abc123&type=magiclink&redirect_to=com.levidahlstrom.RetroStacks://"
        let result = SupabaseAuthClient.extractToken(from: link)
        #expect(result?.token == "pkce_abc123")
        #expect(result?.type == "magiclink")
    }

    @Test func fallsBackToTokenHashWhenThatsWhatTheLinkCarries() {
        let link = "https://vethkqrlcacmlffuzlnx.supabase.co/auth/v1/verify?token_hash=deadbeef&type=email"
        let result = SupabaseAuthClient.extractToken(from: link)
        #expect(result?.token == "deadbeef")
        #expect(result?.type == "email")
    }

    @Test func defaultsToMagicLinkTypeWhenTypeIsMissing() {
        let link = "https://vethkqrlcacmlffuzlnx.supabase.co/auth/v1/verify?token=abc123"
        let result = SupabaseAuthClient.extractToken(from: link)
        #expect(result?.type == "magiclink")
    }

    @Test func toleratesSurroundingWhitespaceFromACopyPaste() {
        let link = "  https://vethkqrlcacmlffuzlnx.supabase.co/auth/v1/verify?token=abc123&type=magiclink  \n"
        let result = SupabaseAuthClient.extractToken(from: link)
        #expect(result?.token == "abc123")
    }

    @Test func returnsNilForTextThatIsntALink() {
        #expect(SupabaseAuthClient.extractToken(from: "") == nil)
        #expect(SupabaseAuthClient.extractToken(from: "not a link at all") == nil)
        #expect(SupabaseAuthClient.extractToken(from: "https://example.com/no-token-here") == nil)
    }

    // MARK: - completeSignIn's actual request shape

    /// Regression test for the real bug found live 2026-09-16: `completeSignIn`
    /// used to POST `{type, token, email}` to `/verify` — the shape for a
    /// *typed-in* numeric OTP code — instead of `{type, token_hash}`, the
    /// shape GoTrue's email-link verification actually requires (confirmed
    /// against the real server: GoTrue rejects `token_hash` + `email` together
    /// with "Only the token_hash and type should be provided"). Every failure
    /// surfaced identically ("Token has expired or is invalid") regardless of
    /// cause, which is what made a wrong request shape indistinguishable from
    /// a genuinely expired token for two days of live debugging. Mocks
    /// `URLSession` at the protocol level — no live network — and asserts the
    /// exact JSON body sent, not just that *a* request went out.
    @Test func completeSignInPostsTokenHashOnlyNoTokenNoEmail() async throws {
        let link = "https://vethkqrlcacmlffuzlnx.supabase.co/auth/v1/verify?token=realhash123&type=magiclink&redirect_to=http://localhost:3000"

        let (session, capturedRequest) = MockURLProtocol.session(
            returning: Self.sampleTokenResponseJSON, status: 200
        )
        let client = SupabaseAuthClient(session: session)

        _ = try await client.completeSignIn(pastedLink: link)

        let body = try #require(capturedRequest.wrappedValue?.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["token_hash"] == "realhash123")
        #expect(json["type"] == "magiclink")
        #expect(json["token"] == nil, "the wrong-shaped field this bug used to send")
        #expect(json["email"] == nil, "GoTrue rejects token_hash verification if email is also present")
    }

    private static let sampleTokenResponseJSON = """
    {
        "access_token": "a.b.c",
        "refresh_token": "r",
        "expires_in": 3600,
        "user": {"id": "09ca3d57-6b3c-4649-b55a-db1797bff97c", "email": "test@example.com"}
    }
    """
    // Fixed literal, always valid UTF-8.
    // swiftlint:disable:next force_unwrapping
    .data(using: .utf8)!
}

/// Minimal `URLProtocol` stub — no live network, no server to run. Captures
/// the one request it intercepts (body + headers) so a test can assert on
/// exactly what was sent, and returns a fixed canned response.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData: Data = Data()
    nonisolated(unsafe) static var responseStatus: Int = 200
    nonisolated(unsafe) static var captured: CapturedRequest?

    final class CapturedRequest: @unchecked Sendable {
        var body: Data?
    }

    static func session(returning json: Data, status: Int) -> (URLSession, Box<CapturedRequest?>) {
        responseData = json
        responseStatus = status
        let captured = CapturedRequest()
        Self.captured = captured

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return (URLSession(configuration: config), Box(captured))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured?.body = request.httpBodyStreamData() ?? request.httpBody
        // `request.url` and these fixed, well-formed HTTPURLResponse
        // parameters can't be nil/fail for a request this test itself built.
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: Self.responseStatus,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Simple reference wrapper so the test can read the captured body after
/// `completeSignIn` runs, without `MockURLProtocol`'s static mutable state
/// leaking into the test's own `Sendable` surface.
private final class Box<T>: @unchecked Sendable {
    var wrappedValue: T
    init(_ value: T) { self.wrappedValue = value }
}

private extension URLRequest {
    /// `URLProtocol.startLoading()` sees `httpBody` as `nil` for requests
    /// built with a body stream in some configurations — fall back to
    /// reading the stream directly so the test doesn't flake on that.
    func httpBodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
