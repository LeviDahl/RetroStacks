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

    static let shared = CatalogSyncService(repository: RemoteCatalogRepository())

    init(repository: CatalogRepository) {
        self.repository = repository
    }

    var lastSynced: Date? {
        if case .synced(let date) = phase { return date }
        return nil
    }

    /// Fetch + reconcile. Safe to call on every launch and from a manual button.
    func sync(into context: ModelContext) async {
        guard phase != .syncing else { return }
        phase = .syncing
        do {
            let feed = try await repository.fetchCatalog()
            try reconcile(feed, into: context)
            if context.hasChanges { try context.save() }
            phase = .synced(.now)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    // MARK: - Reconcile

    private func reconcile(_ feed: CatalogFeed, into context: ModelContext) throws {
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
            platform.name = fp.name
            platform.shortName = fp.shortName
            platform.manufacturer = fp.manufacturer
            platform.generation = fp.generation
            platform.releaseYearNA = fp.releaseYearNA
            platform.discontinuedYearNA = fp.discontinuedYearNA
            platform.summary = fp.summary
            platform.iconSystemName = fp.iconSystemName
            platform.regionsAvailable = fp.regions.compactMap(Region.init(rawValue:))
        }

        var itemsBySlug = Dictionary(
            try context.fetch(FetchDescriptor<CatalogItem>()).map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for fi in feed.items {
            let kind = ItemKind(rawValue: fi.kind) ?? .game
            let item: CatalogItem
            if let existing = itemsBySlug[fi.slug] {
                item = existing
            } else {
                item = CatalogItem(slug: fi.slug, kind: kind, name: fi.name)
                context.insert(item)
                itemsBySlug[fi.slug] = item
            }
            item.kind = kind
            item.name = fi.name
            item.variant = fi.variant
            item.releaseYearNA = fi.releaseYearNA
            item.manufacturerOrPublisher = fi.manufacturerOrPublisher
            item.developer = fi.developer
            item.genre = fi.genre
            item.upc = fi.upc
            item.summary = fi.summary
            item.imageURLString = fi.imageURL
            item.imageCredit = fi.imageCredit
            item.imageLicense = fi.imageLicense
            item.platform = platformsBySlug[fi.platformSlug]
        }
    }
}
