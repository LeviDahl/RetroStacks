import SwiftUI
import SwiftData

struct DashboardView: View {
    var onSelectSection: (AppSection) -> Void = { _ in }

    @Query private var collectionItems: [CollectionItem]

    private var stats: CollectionStats {
        CollectionStatsBuilder.build(from: collectionItems)
    }

    private var systemSummaries: [CollectionStats.SystemSummary] {
        CollectionStatsBuilder.systemSummaries(from: collectionItems, status: .owned)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                statGrid

                if !systemSummaries.isEmpty {
                    PlatformBreakdownCard(summaries: systemSummaries)
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

// MARK: - Platform breakdown (collapsible, metric-switchable bars)

private enum BreakdownMetric: String, CaseIterable, Identifiable {
    case value, games, completion
    var id: String { rawValue }
    var label: String {
        switch self {
        case .value: "Value"
        case .games: "Games"
        case .completion: "Completion"
        }
    }
}

private struct PlatformBreakdownCard: View {
    var summaries: [CollectionStats.SystemSummary]

    @AppStorage("dashboard.breakdownMetric") private var metricRaw = BreakdownMetric.value.rawValue
    @AppStorage("dashboard.breakdownExpanded") private var expanded = true

    private var metric: BreakdownMetric { BreakdownMetric(rawValue: metricRaw) ?? .value }

    /// (summary, bar fraction 0…1, trailing label), sorted by the active metric.
    private var rows: [(summary: CollectionStats.SystemSummary, fraction: Double, label: String)] {
        switch metric {
        case .value:
            let amounts = summaries.map { NSDecimalNumber(decimal: $0.value).doubleValue }
            let maxV = max(amounts.max() ?? 1, 0.01)
            return zip(summaries, amounts)
                .map { ($0, $1 / maxV, Money.string($0.value)) }
                .sorted { $0.1 > $1.1 }
                .map { (summary: $0.0, fraction: $0.1, label: $0.2) }
        case .games:
            let maxC = Double(summaries.map(\.ownedItemCount).max() ?? 1)
            return summaries
                .map { ($0, Double($0.ownedItemCount) / max(maxC, 1), "\($0.ownedItemCount)") }
                .sorted { $0.1 > $1.1 }
                .map { (summary: $0.0, fraction: $0.1, label: $0.2) }
        case .completion:
            return summaries
                .map { ($0, $0.completionRatio, "\($0.completionPercent)%") }
                .sorted { $0.1 > $1.1 }
                .map { (summary: $0.0, fraction: $0.1, label: $0.2) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Breakdown by Platform", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide breakdown" : "Show breakdown")
            }

            if expanded {
                Picker("Metric", selection: $metricRaw) {
                    ForEach(BreakdownMetric.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                VStack(spacing: 8) {
                    ForEach(rows, id: \.summary.id) { row in
                        BreakdownBar(
                            shortName: row.summary.platformShortName,
                            fraction: row.fraction,
                            valueText: row.label,
                            subText: metric == .value ? "\(row.summary.ownedItemCount)" : nil
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }
}

private struct BreakdownBar: View {
    var shortName: String
    var fraction: Double
    var valueText: String
    var subText: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(shortName)
                .font(.callout.weight(.medium))
                .frame(width: 54, alignment: .leading)
                .lineLimit(1)

            GeometryReader { proxy in
                Capsule()
                    .fill(.tint.opacity(0.85))
                    .frame(width: max(4, proxy.size.width * max(0, min(1, fraction))))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 14)

            Text(valueText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)

            if let subText {
                Text(subText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
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
