import Foundation
import Testing

@testable import RetroStacks

/// Regression coverage for the bug found 2026-09-13: `AccountService.init()`
/// used to call `store.load()` (a blocking `SecItemCopyMatching`) inline.
/// `DashboardView` reads `AccountService.shared` from a `@State` initializer,
/// which runs synchronously on the main thread during that view's first
/// render — the blocking Keychain call delayed the window appearing at all
/// under XCUITest hosting on macOS (confirmed via the accessibility-hierarchy
/// dump of the failing tests: it showed only the menu bar, no app window).
///
/// `SupabaseSessionStore.shared` is real Keychain, not a fake — there's no
/// abstraction to fake it behind, and it's cheap/side-effect-free enough
/// (a single generic-password item under this app's own service string) to
/// use directly in a test, same as any other local-only Keychain test would.
@Suite(.serialized)
struct AccountServiceTests {

    private func sampleSession(userID: UUID = UUID()) -> SupabaseSession {
        SupabaseSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: .now.addingTimeInterval(3600),
            userID: userID,
            email: "collector@example.com"
        )
    }

    @MainActor
    @Test func initReturnsBeforeRestoringAnExistingSession() async throws {
        let store = SupabaseSessionStore.shared
        store.save(sampleSession())
        defer { store.clear() }

        let service = AccountService(store: store)
        // No `await` has happened yet — the restore Task hasn't had a chance
        // to run. This is the actual regression check: before the fix, this
        // was already `.signedIn` here because the load was inline.
        #expect(service.state == .signedOut)

        // Yield a few times to let the deferred Task actually run.
        for _ in 0..<5 where !service.state.isSignedIn {
            await Task.yield()
        }
        #expect(service.state.isSignedIn)
    }

    @MainActor
    @Test func initWithNoStoredSessionStaysSignedOut() async throws {
        let store = SupabaseSessionStore.shared
        store.clear()

        let service = AccountService(store: store)
        for _ in 0..<5 { await Task.yield() }
        #expect(service.state == .signedOut)
    }

    @MainActor
    @Test func signOutClearsStateAndStore() async throws {
        let store = SupabaseSessionStore.shared
        store.save(sampleSession())

        let service = AccountService(store: store)
        for _ in 0..<5 where !service.state.isSignedIn {
            await Task.yield()
        }
        #expect(service.state.isSignedIn)

        service.signOut()
        #expect(service.state == .signedOut)
        #expect(store.load() == nil)
    }

    // MARK: - SupabaseSessionStore (no prior direct coverage)

    /// Same `.serialized` suite as the tests above deliberately — every test
    /// here touches the same real Keychain item (`SupabaseSessionStore.shared`
    /// has no test seam to fake), so cross-test interleaving would be flaky.
    @Test func sessionStoreSaveLoadClearRoundTrips() {
        let store = SupabaseSessionStore.shared
        store.clear()
        #expect(store.load() == nil)

        let session = SupabaseSession(
            accessToken: "a", refreshToken: "b",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            userID: UUID(), email: "test@example.com"
        )
        store.save(session)
        #expect(store.load() == session)

        // Saving again (the update path, not the insert path) should overwrite cleanly.
        var updated = session
        updated.accessToken = "c"
        store.save(updated)
        #expect(store.load() == updated)

        store.clear()
        #expect(store.load() == nil)
    }
}
