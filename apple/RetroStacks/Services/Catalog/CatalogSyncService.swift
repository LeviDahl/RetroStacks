import Foundation
import Observation
import SwiftData

/// Pulls the reference catalog from the data feed and reconciles it into
/// SwiftData, keyed by `slug`. Additive for now — items that vanish from the
/// feed are left in place until the real catalog stabilises.
///
/// Never throws out to the caller: if the fetch fails, whatever's already in the
/// store (the `SampleData` seed, or the last successful sync) stays put.
@MainActor
@Observable
final class CatalogSyncService {
    enum Phase: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let repository: CatalogRepository
    /// Remembered so the status badge's Retry can re-run without a view handy.
    /// It's the app-lifetime `mainContext`, so holding it is harmless.
    private var lastContext: ModelContext?

    static let shared = CatalogSyncService(repository: RemoteCatalogRepository())

    init(repository: CatalogRepository) {
        self.repository = repository
    }

    /// Re-run the last sync as a forced reload. No-op if we've never synced.
    func retry() {
        guard let context = lastContext else { return }
        Task { await sync(into: context, forceReload: true) }
    }

    var lastSynced: Date? {
        if case .synced(let date) = phase { return date }
        return nil
    }

    /// Fetch + reconcile. Safe to call on every launch; pass `forceReload` from a
    /// manual "Sync now" to bypass the HTTP cache entirely.
    func sync(into context: ModelContext, forceReload: Bool = false) async {
        guard phase != .syncing else { return }
        lastContext = context
        phase = .syncing
        do {
            let feed = try await repository.fetchCatalog(forceReload: forceReload)
            try await reconcile(feed, into: context)
            if context.hasChanges { try context.save() }
            phase = .synced(.now)
            AppStatusCenter.shared.clear(.catalogSync)
        } catch {
            phase = .failed(String(describing: error))
            let message = (error as? CatalogError)?.userMessage ?? error.localizedDescription
            AppStatusCenter.shared.report(
                .catalogSync,
                severity: .warning,
                title: "Catalog didn’t update",
                detail: "\(message) Showing the last synced copy.",
                retry: { CatalogSyncService.shared.retry() }
            )
        }
    }

    // MARK: - Reconcile

    private func reconcile(_ feed: CatalogFeed, into context: ModelContext) async throws {
        var platformsBySlug = Dictionary(
            try context.fetch(FetchDescriptor<Platform>()).map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for fp in feed.platforms {
            let platform: Platform
            if let existing = platformsBySlug[fp.slug] {
                platform = existing
            } else {
                platform = Platform(slug: fp.slug, name: fp.name, shortName: fp.shortName,
                                    manufacturer: fp.manufacturer, generation: fp.generation)
                context.insert(platform)
                platformsBySlug[fp.slug] = platform
            }
            // Only write changed fields — the catalog is thousands of rows and
            // this runs on every launch; equal-value assignments still dirty the row.
            func set<V: Equatable>(_ kp: ReferenceWritableKeyPath<Platform, V>, _ v: V) {
                if platform[keyPath: kp] != v { platform[keyPath: kp] = v }
            }
            set(\.name, fp.name)
            set(\.shortName, fp.shortName)
            set(\.manufacturer, fp.manufacturer)
            set(\.generation, fp.generation)
            set(\.releaseYearNA, fp.releaseYearNA)
            set(\.discontinuedYearNA, fp.discontinuedYearNA)
            set(\.summary, fp.summary)
            set(\.iconSystemName, fp.iconSystemName)
            let regions = fp.regions.compactMap(Region.init(rawValue:))
            if platform.regionsAvailable != regions { platform.regionsAvailable = regions }
        }

        var itemsBySlug = Dictionary(
            try context.fetch(FetchDescriptor<CatalogItem>()).map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var processed = 0
        for fi in feed.items {
            processed += 1
            if processed % 400 == 0 {
                if context.hasChanges { try? context.save() }
                await Task.yield()
            }
            let kind = ItemKind(rawValue: fi.kind) ?? .game
            let item: CatalogItem
            if let existing = itemsBySlug[fi.slug] {
                item = existing
            } else {
                item = CatalogItem(slug: fi.slug, kind: kind, name: fi.name)
                context.insert(item)
                itemsBySlug[fi.slug] = item
            }
            func set<V: Equatable>(_ kp: ReferenceWritableKeyPath<CatalogItem, V>, _ v: V) {
                if item[keyPath: kp] != v { item[keyPath: kp] = v }
            }
            if item.kind != kind { item.kind = kind }
            set(\.name, fi.name)
            set(\.variant, fi.variant)
            set(\.releaseYearNA, fi.releaseYearNA)
            set(\.manufacturerOrPublisher, fi.manufacturerOrPublisher)
            set(\.developer, fi.developer)
            set(\.genre, fi.genre)
            set(\.upc, fi.upc)
            set(\.summary, fi.summary ?? "")
            set(\.imageURLString, fi.imageURL)
            set(\.imageCredit, fi.imageCredit)
            set(\.imageLicense, fi.imageLicense)
            let platform = platformsBySlug[fi.platformSlug]
            if item.platform?.slug != platform?.slug { item.platform = platform }
        }
    }
}
