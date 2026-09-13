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
}
