import Foundation
import SwiftData

/// What a `CatalogPlatformRow` needs per platform: the visible entry count
/// and a console image. Each row used to compute both from the platform's
/// full `catalogItems` relationship inside `body` (`platform.consoles` +
/// `visibleCatalogItems()`, an `isHidden` getter per item) — ~1.3s of main
/// thread on every visit to Catalog, per a live `sample` 2026-09-19.
nonisolated struct PlatformOverview: Sendable, Equatable {
    var heroImageURL: URL?
    var entryCount: Int

    /// One pass over every catalog item, grouped by platform slug.
    static func compute(from items: [CatalogItem], includeHidden: Bool) -> [String: PlatformOverview] {
        var result: [String: PlatformOverview] = [:]
        var consoleHero: [String: URL] = [:]
        var anyConsole: Set<String> = []
        for item in items {
            guard let slug = item.platform?.slug, includeHidden || !item.isHidden else { continue }
            result[slug, default: PlatformOverview(heroImageURL: nil, entryCount: 0)].entryCount += 1
            if item.kind == .console {
                anyConsole.insert(slug)
                if consoleHero[slug] == nil, let url = item.imageURL { consoleHero[slug] = url }
            }
        }
        for slug in anyConsole { result[slug]?.heroImageURL = consoleHero[slug] }
        return result
    }
}

@ModelActor
actor PlatformOverviewActor {
    func overviews(includeHidden: Bool) throws -> [String: PlatformOverview] {
        PlatformOverview.compute(from: try modelContext.fetch(FetchDescriptor<CatalogItem>()), includeHidden: includeHidden)
    }
}

extension PlatformOverviewActor {
    /// `@concurrent` so the actor is built off the main thread — see
    /// `CollectionSummariesActor.summaries`.
    @concurrent
    static func overviews(container: ModelContainer) async throws -> [String: PlatformOverview] {
        try await PlatformOverviewActor(modelContainer: container).overviews(
            includeHidden: UserDefaults.standard.bool(forKey: "system.showHidden")
        )
    }
}

/// Stale-while-revalidate snapshot shared by every platform row (one compute
/// for all of them, joined while in flight). Invalidated together with
/// `SystemSummariesCache` on catalog sync / hide.
@MainActor
enum PlatformOverviewCache {
    static let maxAge: TimeInterval = 60
    private static var snapshot: [String: PlatformOverview]?
    private static var computedAt = Date.distantPast
    private static var invalidated = false
    private static var inFlight: Task<Void, Never>?

    static func invalidate() { invalidated = true }

    static func overview(for slug: String, container: ModelContainer) async -> PlatformOverview? {
        if let snapshot {
            if invalidated || Date.now.timeIntervalSince(computedAt) >= maxAge { refresh(container) }
            return snapshot[slug]
        }
        refresh(container)
        await inFlight?.value
        return snapshot?[slug]
    }

    private static func refresh(_ container: ModelContainer) {
        guard inFlight == nil else { return }
        inFlight = Task {
            if let result = try? await PlatformOverviewActor.overviews(container: container) {
                snapshot = result
                computedAt = .now
                invalidated = false
            }
            inFlight = nil
        }
    }
}
