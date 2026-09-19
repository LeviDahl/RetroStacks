import Foundation
import SwiftData

/// Runs `CollectionStatsBuilder.systemSummaries` off the main actor. It
/// groups every owned/wishlisted item by platform and walks each platform's
/// full visible catalog (a `CatalogItem.isHidden` getter per item), which a
/// real `sample` of the live app 2026-09-19 measured at ~6s of a 30s window
/// of Collection/Wishlist clicking — all on the main thread, inside a `.task`
/// (which is `@MainActor` by default here, so "deferred" was never the same
/// as "off the main thread"). Same pattern as `CatalogQueryActor`; the
/// result is a plain `Sendable` value type, so nothing model-shaped crosses
/// back.
@ModelActor
actor CollectionSummariesActor {
    /// Test seam: where does this actor actually execute?
    func runsOnMainThread() -> Bool { Thread.isMainThread }

    func systemSummaries(status: CollectionStatus) throws -> [CollectionStats.SystemSummary] {
        let items = try modelContext.fetch(
            FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return CollectionStatsBuilder.systemSummaries(from: items, status: status)
    }
}

extension CollectionSummariesActor {
    /// The only way call sites should run this. A `@ModelActor` created from
    /// a `@MainActor` context runs its methods on the main thread — a second
    /// `sample` (2026-09-19) showed ~11s of a 26s window still on main inside
    /// `systemSummaries` despite the actor. `@concurrent` builds the actor on
    /// the global pool so it (and its context) are genuinely off-main.
    @concurrent
    static func summaries(
        container: ModelContainer, status: CollectionStatus
    ) async throws -> [CollectionStats.SystemSummary] {
        let actor = CollectionSummariesActor(modelContainer: container)
        return try await actor.systemSummaries(status: status)
    }
}

extension CollectionSummariesActor {
    /// Test seam: builds the actor the same way `summaries` does and reports
    /// whether it ended up on the main thread.
    @concurrent
    static func runsOnMainThread(container: ModelContainer) async -> Bool {
        await CollectionSummariesActor(modelContainer: container).runsOnMainThread()
    }
}
