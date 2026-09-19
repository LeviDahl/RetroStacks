import Foundation
import Testing

@testable import RetroStacks

/// The cache is what keeps Dashboard/My Collection from showing a spinner on
/// every sidebar switch (~1-2s recompute). Freshness rules, not the compute.
@MainActor
struct SystemSummariesCacheTests {
    private func entry(key: Int = 1, age: TimeInterval = 0, invalidated: Bool = false) -> SystemSummariesCache.Entry {
        SystemSummariesCache.Entry(
            key: key, computedAt: Date(timeIntervalSinceNow: -age), value: [], invalidated: invalidated
        )
    }

    @Test func freshOnlyWhenKeyMatchesAndYoungAndNotInvalidated() {
        #expect(entry().isFresh(for: 1))
        #expect(!entry().isFresh(for: 2))
        #expect(!entry(age: SystemSummariesCache.maxAge + 1).isFresh(for: 1))
        #expect(!entry(invalidated: true).isFresh(for: 1))
    }
}
