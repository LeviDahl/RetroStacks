import SwiftUI
import SwiftData

struct DashboardView: View {
    var onSelectSection: (AppSection) -> Void = { _ in }

    @Query private var collectionItems: [CollectionItem]
    @AppStorage("dashboard.showBreakdown") private var showBreakdown = true

    private var stats: CollectionStats {
        CollectionStatsBuilder.build(from: collectionItems)
    }

    private var systemSummaries: [CollectionStats.SystemSummary] {
        CollectionStatsBuilder.systemSummaries(from: collectionItems, status: .owned)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                collectionHeader

                statGrid

                if showBreakdown && !systemSummaries.isEmpty {
                    PlatformBreakdownCard(summaries: systemSummaries)
                }

                twoColumnLists
            }
            .padding(LayoutMetrics.screenEdgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .appNavigationDestinations()
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Menu {
                    Toggle("Platform Breakdown", isOn: $showBreakdown)
                } label: {
                    Label("View Options", systemImage: "slider.horizontal.3")
                }
            }
            ToolbarItem {
                Button {
                    onSelectSection(.catalog)
                } label: {
                    Label("Browse Catalog", systemImage: "books.vertical")
                }
            }
        }
    }

    /// Retro Game Collector-style headline: the one big number, with context.
    /// Trailing stat cluster drops out when the width is tight (phones) — the
    /// same figures are in the stat grid right below.
    private var collectionHeader: some View {
        let games = stats.ownedByKind[.game] ?? 0
        let systems = systemSummaries.count

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                bigNumber(games)
                Spacer(minLength: 8)
                HStack(spacing: 22) {
                    headerStat("\(systems)", systems == 1 ? "system" : "systems")
                    headerStat("\(stats.ownedCount)", "items")
                    headerStat(Money.string(stats.estimatedValue), "est. value")
                }
            }
            bigNumber(games)
        }
    }

    private func bigNumber(_ games: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(games, format: .number)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(games == 1 ? "game in your collection" : "games in your collection")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Label("Breakdown by Platform", systemImage: "chart.bar.xaxis")
                .font(.headline)

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
                        color: PlatformPalette.color(for: row.summary.platformSlug),
                        valueText: row.label,
                        subText: metric == .value ? "\(row.summary.ownedItemCount)" : nil
                    )
                }
            }
            .animation(.snappy(duration: 0.25), value: metricRaw)
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
    var color: Color
    var valueText: String
    var subText: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(shortName)
                .font(.callout.weight(.medium))
                .frame(width: 54, alignment: .leading)
                .lineLimit(1)

            GeometryReader { proxy in
                let clamped = max(0, min(1, fraction))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.5))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.65)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, proxy.size.width * clamped))
                }
            }
            .frame(height: 15)

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
