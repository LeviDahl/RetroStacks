import Foundation
import SwiftData

/// Last computed per-system summaries, shared by Dashboard and My Collection.
/// The compute (`CollectionSummariesActor`) is off-main but still ~1-2s: it
/// faults in every catalog item of every owned platform. Both screens are
/// rebuilt on every sidebar switch, so recomputing each visit meant a spinner
/// each visit (user report + `sample`, 2026-09-19). Now a visit shows the last
/// result immediately and only recomputes when the collection changed, the
/// entry is older than `maxAge`, or a catalog sync / hide `invalidate()`d it.
@MainActor
enum SystemSummariesCache {
    struct Entry {
        var key: Int
        var computedAt: Date
        var value: [CollectionStats.SystemSummary]
        var invalidated = false

        func isFresh(for key: Int, now: Date = .now, maxAge: TimeInterval = SystemSummariesCache.maxAge) -> Bool {
            !invalidated && self.key == key && now.timeIntervalSince(computedAt) < maxAge
        }
    }

    static let maxAge: TimeInterval = 60
    private static var entries: [CollectionStatus: Entry] = [:]

    static func key(items: [CollectionItem], status: CollectionStatus) -> Int {
        var hasher = Hasher()
        for item in items { hasher.combine(item.persistentModelID) }
        hasher.combine(status)
        return hasher.finalize()
    }

    static func entry(for status: CollectionStatus) -> Entry? { entries[status] }

    /// Catalog contents changed (sync finished, item hidden/excluded).
    static func invalidate() {
        for status in entries.keys { entries[status]?.invalidated = true }
        PlatformOverviewCache.invalidate()
    }

    static func reset() { entries = [:] }

    /// Calls `show` right away with any cached value, then recomputes off-main
    /// only if that value isn't fresh for `key`.
    static func load(
        container: ModelContainer, status: CollectionStatus, key: Int,
        show: ([CollectionStats.SystemSummary]) -> Void
    ) async {
        if let entry = entries[status] {
            show(entry.value)
            if entry.isFresh(for: key) { return }
        }
        guard let result = try? await CollectionSummariesActor.summaries(container: container, status: status),
              !Task.isCancelled else { return }
        entries[status] = Entry(key: key, computedAt: .now, value: result)
        show(result)
    }
}

extension ModelContext {
    /// For saves that change catalog visibility (hide / exclude): the cached
    /// per-system counts are now wrong.
    @MainActor
    func saveInvalidatingSummaries() {
        SystemSummariesCache.invalidate()
        saveLoggingErrors(reportingAs: .localSave)
    }
}
