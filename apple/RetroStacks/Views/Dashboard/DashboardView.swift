import SwiftUI
import SwiftData

struct DashboardView: View {
    var onSelectSection: (AppSection) -> Void = { _ in }

    @Query(filter: #Predicate<CollectionItem> { $0.deletedAt == nil })
    private var collectionItems: [CollectionItem]
    @Query(sort: \Platform.generation) private var platforms: [Platform]
    @AppStorage("dashboard.showBreakdown") private var showBreakdown = true

    @Environment(\.modelContext) private var modelContext
    @State private var sync = CatalogSyncService.shared
    @State private var account = AccountService.shared
    @State private var collectionSync = SyncCoordinator.shared
    @State private var showingSignIn = false

    /// `Font.system(size: 46, ...)` is a literal point size — it does **not**
    /// grow with Dynamic Type on its own, unlike `.largeTitle`/`.title` text
    /// styles. `@ScaledMetric` is the fix for "I want this exact point size at
    /// the default text size, but it should still scale up at larger
    /// accessibility sizes like everything else on the screen."
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumberSize: CGFloat = 46

    private var stats: CollectionStats {
        CollectionStatsBuilder.build(from: collectionItems)
    }

    private var syncMenuLabel: String {
        switch sync.phase {
        case .syncing: "Syncing catalog…"
        case .synced(let date): "Catalog synced \(date.formatted(.relative(presentation: .named)))"
        case .failed: "Catalog sync failed — retry"
        case .idle: "Sync catalog now"
        }
    }

    private var collectionSyncMenuLabel: String {
        switch collectionSync.phase {
        case .syncing: "Syncing collection…"
        case .synced(let date): "Collection synced \(date.formatted(.relative(presentation: .named)))"
        case .failed: "Collection sync failed — retry"
        case .idle: "Sync collection now"
        }
    }

    private var systemSummaries: [CollectionStats.SystemSummary] {
        CollectionStatsBuilder.systemSummaries(from: collectionItems, status: .owned)
    }

    /// Self-contained, like every other section — `NavigationLink`s inside
    /// Dashboard need their own `NavigationStack` to push into. Without one, a
    /// `NavigationLink` fired from inside a `NavigationSplitView`'s detail
    /// column tries to target a column *after* detail — which doesn't exist —
    /// and silently fails (Xcode logs "There is no next column after the
    /// detail column"). Only mattered on macOS/iPadOS: the iPhone tab layout
    /// used to paper over this by wrapping Dashboard in its own stack, which
    /// is also why this went unnoticed until the breakdown row's link was
    /// click-tested on macOS.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    collectionHeader

                    statGrid

                    if showBreakdown && !systemSummaries.isEmpty {
                        PlatformBreakdownCard(summaries: systemSummaries, platforms: platforms)
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
                        Divider()
                        Button {
                            Task { await sync.sync(into: modelContext, forceReload: true) }
                        } label: {
                            Label(syncMenuLabel, systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sync.phase == .syncing)
                        if account.state.isSignedIn {
                            Button {
                                Task { await collectionSync.sync(into: modelContext) }
                            } label: {
                                Label(collectionSyncMenuLabel, systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(collectionSync.phase == .syncing)
                        }
                        Divider()
                        Button {
                            showingSignIn = true
                        } label: {
                            Label(account.summary, systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier(AccessibilityID.Account.signInRow)
                        if account.state.isSignedIn {
                            Button(role: .destructive) {
                                account.signOut()
                            } label: {
                                Label("Sign Out", systemImage: "person.crop.circle.badge.xmark")
                            }
                        }
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
            .sheet(isPresented: $showingSignIn) { SignInSheet() }
            .onChange(of: account.state) { _, newValue in
                // Sign-in just completed — pull the collection down immediately
                // rather than waiting for the next launch/foreground.
                if newValue.isSignedIn {
                    Task { await collectionSync.sync(into: modelContext) }
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
                .font(.system(size: bigNumberSize, weight: .bold, design: .rounded))
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
                     footnote: kindBreakdown,
                     action: { onSelectSection(.collection) })
                .accessibilityIdentifier(AccessibilityID.Dashboard.ownedItemsTile)
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
    var platforms: [Platform]

    @AppStorage("dashboard.breakdownMetric") private var metricRaw = BreakdownMetric.value.rawValue

    private var metric: BreakdownMetric { BreakdownMetric(rawValue: metricRaw) ?? .value }

    private func platform(for slug: String) -> Platform? {
        platforms.first { $0.slug == slug }
    }

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
                        icon: row.summary.iconSystemName,
                        imageURL: row.summary.heroImageURL,
                        shortName: row.summary.platformShortName,
                        platform: platform(for: row.summary.platformSlug),
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
    var icon: String
    var imageURL: URL?
    var shortName: String
    /// When present, the icon/name (only — not the bar or value) links to that
    /// system's collection screen.
    var platform: Platform?
    var fraction: Double
    var color: Color
    var valueText: String
    var subText: String?

    @Environment(\.horizontalSizeClass) private var hSize
    private var compact: Bool { hSize == .compact }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            label
                .frame(width: compact ? 80 : 92, alignment: .leading)

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
                .frame(width: compact ? 64 : 78, alignment: .trailing)

            if let subText, !compact {
                Text(subText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if let platform {
            NavigationLink(value: platform) { labelContent }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.Dashboard.breakdownRow(platform.slug))
        } else {
            labelContent
        }
    }

    private var labelContent: some View {
        HStack(spacing: 6) {
            ItemThumbnail(
                kind: .console,
                platformSymbol: icon,
                imageURL: imageURL,
                size: 22, cornerRadius: 5, contentMode: .fit
            )
            Text(shortName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .contentShape(Rectangle())
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
