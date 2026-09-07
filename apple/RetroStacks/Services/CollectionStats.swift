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

    var recentlyAdded: [CollectionItem] = []
    var mostValuable: [CollectionItem] = []

    /// One row of the system-first Collection view: how much of a platform you
    /// have, how complete it is, and what it's worth.
    struct SystemSummary: Identifiable {
        var id: String { platformSlug }
        var platformSlug: String
        var platformName: String
        var platformShortName: String
        var iconSystemName: String
        var heroImageURL: URL?
        var ownedItemCount: Int
        var ownedGameCount: Int
        var catalogGameCount: Int
        var value: Decimal
        /// Sum of reference prices for catalogued games on this platform you
        /// don't own — roughly "what finishing the set would cost".
        var remainingValue: Decimal
        /// 0…1, `ownedGameCount / catalogGameCount` (0 when the catalog has no games yet).
        var completionRatio: Double

        var completionPercent: Int { Int((completionRatio * 100).rounded()) }
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

    /// System-first breakdown for the Collection view: one `SystemSummary` per
    /// platform the user has at least one item on (for the given status).
    /// Sorted by item count, then value, descending.
    static func systemSummaries(
        from items: [CollectionItem],
        status: CollectionStatus
    ) -> [CollectionStats.SystemSummary] {
        let scoped = items.filter { $0.status == status }

        var groups: [String: [CollectionItem]] = [:]
        for item in scoped {
            guard let slug = item.catalogItem?.platform?.slug else { continue }
            groups[slug, default: []].append(item)
        }

        return groups.compactMap { slug, group -> CollectionStats.SystemSummary? in
            guard let platform = group.first?.catalogItem?.platform else { return nil }
            let ownedGames = group.filter { $0.kind == .game }.count
            let games = platform.games
            let ownedSlugs = Set(group.compactMap { $0.catalogItem?.slug })
            let remaining = games
                .filter { !ownedSlugs.contains($0.slug) }
                .compactMap(\.headlineValue)
                .reduce(Decimal(0), +)
            let hero = (platform.consoles.first { $0.imageURL != nil } ?? platform.consoles.first)?.imageURL
            return CollectionStats.SystemSummary(
                platformSlug: slug,
                platformName: platform.name,
                platformShortName: platform.shortName,
                iconSystemName: platform.iconSystemName,
                heroImageURL: hero,
                ownedItemCount: group.count,
                ownedGameCount: ownedGames,
                catalogGameCount: games.count,
                value: group.compactMap(\.estimatedValue).reduce(0, +),
                remainingValue: remaining,
                completionRatio: games.count > 0
                    ? min(1, Double(ownedGames) / Double(games.count)) : 0
            )
        }
        .sorted { ($0.ownedItemCount, $0.value) > ($1.ownedItemCount, $1.value) }
    }
}
