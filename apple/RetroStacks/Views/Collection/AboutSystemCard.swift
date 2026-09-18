import SwiftUI
import SwiftData

/// The "mini-wiki" header inside a system drill-down: hardware photo, the
/// one-paragraph context blurb, and a fact grid. Collapsible — the drill-down is
/// primarily for managing your collection, this is reference material on top.
struct AboutSystemCard: View {
    var platform: Platform
    var summary: CollectionStats.SystemSummary?

    private var heroConsole: CatalogItem? {
        platform.consoles.first { $0.imageURL != nil } ?? platform.consoles.first
    }

    private var yearRange: String {
        let start = platform.releaseYearNA.map(String.init) ?? "?"
        let end = platform.discontinuedYearNA.map(String.init) ?? "—"
        return "\(start)–\(end)"
    }

    private var ownedCount: Int { platform.catalogItems.filter(\.isOwned).count }
    private var wishlistCount: Int { platform.catalogItems.filter(\.isWishlisted).count }

    /// "1,043 games · 2 consoles · 2 accessories" under the plain total —
    /// user's own follow-up after noticing "Catalog" (all kinds) and My
    /// Collection's per-system ratio (games-only) disagreed by exactly the
    /// hardware/accessory count. `nil` when there's only one kind present
    /// (the overwhelming majority of platforms), so the breakdown doesn't
    /// clutter the common case where it'd just repeat the total.
    private var catalogBreakdown: String? {
        let counts: [(count: Int, label: String)] = [
            (platform.games.count, "games"),
            (platform.consoles.count, "consoles"),
            (platform.accessories.count, "accessories")
        ].filter { $0.count > 0 }
        guard counts.count > 1 else { return nil }
        return counts.map { "\($0.count) \($0.label)" }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Group {
                    if let url = heroConsole?.imageURL {
                        ItemThumbnail(kind: .console, platformSymbol: platform.iconSystemName,
                                      imageURL: url, size: 78, cornerRadius: 14, contentMode: .fit)
                            .accessibilityHidden(true) // decorative — the platform name is read separately below
                    } else {
                        Image(systemName: platform.iconSystemName)
                            .font(.system(size: 34))
                            .foregroundStyle(.tint)
                            .frame(width: 78, height: 78)
                            .background(.tint.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(platform.manufacturer) · \(platform.eraLabel)")
                        .font(.callout).foregroundStyle(.mutedText)
                    if !platform.summary.isEmpty {
                        Text(platform.summary)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !platform.regionsAvailable.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(platform.regionsAvailable) { region in
                                Text("\(region.flagSymbol) \(region.displayName)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                SystemFactTile(label: "Years", value: yearRange)
                SystemFactTile(label: "Generation", value: "\(platform.generation)")
                SystemFactTile(label: "Catalog", value: "\(platform.visibleCatalogItems().count)", detail: catalogBreakdown)
                SystemFactTile(label: "Owned", value: "\(ownedCount)")
                SystemFactTile(label: "Wishlist", value: "\(wishlistCount)")
                SystemFactTile(label: "Value", value: Money.string(summary?.value ?? 0))
            }
        }
    }

    private var columns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 120), spacing: 8)]
        #else
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        #endif
    }
}

struct SystemFactTile: View {
    var label: String
    var value: String
    var detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.mutedText)
            Text(value).font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.mutedText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    let container = SampleData.previewContainer()
    // #Preview only, fixture data is always valid.
    // swiftlint:disable:next force_try
    let platform = try! container.mainContext.fetch(FetchDescriptor<Platform>())
        // "snes" is always seeded.
        // swiftlint:disable:next force_unwrapping
        .first { $0.slug == "snes" }!
    ScrollView { AboutSystemCard(platform: platform).padding() }
        .modelContainer(container)
}
