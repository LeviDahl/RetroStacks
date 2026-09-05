import SwiftUI
import SwiftData

struct DashboardView: View {
    var onSelectSection: (AppSection) -> Void = { _ in }

    @Query private var collectionItems: [CollectionItem]

    private var stats: CollectionStats {
        CollectionStatsBuilder.build(from: collectionItems)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                statGrid

                if !stats.valueByPlatform.isEmpty {
                    DashboardSection(title: "Value by Platform", systemImage: "chart.bar.fill") {
                        ValueByPlatformView(entries: stats.valueByPlatform,
                                            total: stats.estimatedValue)
                    }
                }

                twoColumnLists
            }
            .padding(LayoutMetrics.screenEdgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .gameTrackerDestinations()
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    onSelectSection(.catalog)
                } label: {
                    Label("Browse Catalog", systemImage: "books.vertical")
                }
            }
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: LayoutMetrics.cardColumns(), spacing: LayoutMetrics.cardSpacing) {
            StatTile(title: "Owned Items", value: "\(stats.ownedCount)",
                     systemImage: "square.grid.2x2", tint: .indigo,
                     footnote: kindBreakdown)
            StatTile(title: "Estimated Value", value: Money.string(stats.estimatedValue),
                     systemImage: "chart.line.uptrend.xyaxis", tint: .green,
                     footnote: stats.totalInvested > 0
                        ? "\(Money.signedString(stats.netGain)) vs. invested" : nil,
                     footnoteColor: stats.netGain < 0 ? .red : .green)
            StatTile(title: "Total Invested", value: Money.string(stats.totalInvested),
                     systemImage: "creditcard", tint: .blue)
            StatTile(title: "Wishlist", value: "\(stats.wishlistCount)",
                     systemImage: "star", tint: .yellow,
                     footnote: stats.forSaleCount > 0 ? "\(stats.forSaleCount) marked for sale" : nil)
        }
    }

    private var twoColumnLists: some View {
        let columns: [GridItem] = {
            #if os(macOS)
            [GridItem(.flexible(), spacing: LayoutMetrics.cardSpacing),
             GridItem(.flexible(), spacing: LayoutMetrics.cardSpacing)]
            #else
            [GridItem(.flexible())]
            #endif
        }()

        return LazyVGrid(columns: columns, alignment: .leading, spacing: LayoutMetrics.cardSpacing) {
            DashboardSection(title: "Recently Added", systemImage: "clock") {
                MiniCollectionList(items: stats.recentlyAdded,
                                   emptyText: "Nothing added yet.")
            }
            DashboardSection(title: "Most Valuable", systemImage: "trophy") {
                MiniCollectionList(items: stats.mostValuable,
                                   emptyText: "Add owned items to see your top pieces.")
            }
        }
    }

    private var kindBreakdown: String {
        let parts = ItemKind.allCases.compactMap { kind -> String? in
            let count = stats.ownedByKind[kind] ?? 0
            return count > 0 ? "\(count) \(count == 1 ? kind.displayName.lowercased() : kind.pluralName.lowercased())" : nil
        }
        return parts.isEmpty ? "No items yet" : parts.joined(separator: " · ")
    }
}

// MARK: - Section container

private struct DashboardSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }
}

// MARK: - Value by platform bars

private struct ValueByPlatformView: View {
    var entries: [CollectionStats.PlatformValue]
    var total: Decimal

    private var maxValue: Decimal {
        entries.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    Text(entry.platformShortName)
                        .font(.callout.weight(.medium))
                        .frame(width: 52, alignment: .leading)

                    GeometryReader { proxy in
                        let ratio = fraction(entry.value)
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(4, proxy.size.width * ratio))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 14)

                    Text(Money.string(entry.value))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)

                    Text("\(entry.itemCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }

    private func fraction(_ value: Decimal) -> Double {
        let v = NSDecimalNumber(decimal: value).doubleValue
        let m = NSDecimalNumber(decimal: maxValue).doubleValue
        return m > 0 ? v / m : 0
    }
}

// MARK: - Mini list

private struct MiniCollectionList: View {
    var items: [CollectionItem]
    var emptyText: String

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        CollectionItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id { Divider() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(SampleData.previewContainer())
}
