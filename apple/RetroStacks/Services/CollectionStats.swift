import Foundation

/// Aggregate numbers for the Dashboard. Holds references to `CollectionItem`
/// model objects for the "recent / most valuable" lists, so it is intentionally
/// **not** `Sendable` — build and read it on the main actor with the UI.
struct CollectionStats {
    var ownedCount: Int = 0
    var wishlistCount: Int = 0
    var forSaleCount: Int = 0

    var ownedByKind: [ItemKind: Int] = [:]

    var totalInvested: Decimal = 0
    var estimatedValue: Decimal = 0

    /// Per-platform estimated value of owned items, richest first.
    var valueByPlatform: [PlatformValue] = []

    var recentlyAdded: [CollectionItem] = []
    var mostValuable: [CollectionItem] = []

    struct PlatformValue: Identifiable, Equatable, Sendable {
        var id: String { platformSlug }
        var platformSlug: String
        var platformShortName: String
        var itemCount: Int
        var value: Decimal
    }

    var netGain: Decimal { estimatedValue - totalInvested }

    var netGainRatio: Double {
        guard totalInvested > 0 else { return 0 }
        return NSDecimalNumber(decimal: netGain).doubleValue
            / NSDecimalNumber(decimal: totalInvested).doubleValue
    }
}

enum CollectionStatsBuilder {
    /// Builds stats from every `CollectionItem` in the store.
    static func build(from items: [CollectionItem]) -> CollectionStats {
        var stats = CollectionStats()

        let owned = items.filter { $0.status == .owned }
        stats.ownedCount = owned.count
        stats.wishlistCount = items.filter { $0.status == .wishlist }.count
        stats.forSaleCount = items.filter { $0.status == .forSale }.count

        for kind in ItemKind.allCases {
            stats.ownedByKind[kind] = owned.filter { $0.kind == kind }.count
        }

        stats.totalInvested = owned.compactMap(\.pricePaid).reduce(0, +)
        stats.estimatedValue = owned.compactMap(\.estimatedValue).reduce(0, +)

        var buckets: [String: CollectionStats.PlatformValue] = [:]
        for item in owned {
            guard let platform = item.catalogItem?.platform else { continue }
            var bucket = buckets[platform.slug] ?? .init(
                platformSlug: platform.slug,
                platformShortName: platform.shortName,
                itemCount: 0,
                value: 0
            )
            bucket.itemCount += 1
            bucket.value += item.estimatedValue ?? 0
            buckets[platform.slug] = bucket
        }
        stats.valueByPlatform = buckets.values.sorted { $0.value > $1.value }

        stats.recentlyAdded = items
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(5)
            .map { $0 }

        stats.mostValuable = owned
            .sorted { ($0.estimatedValue ?? 0) > ($1.estimatedValue ?? 0) }
            .prefix(5)
            .map { $0 }

        return stats
    }
}
