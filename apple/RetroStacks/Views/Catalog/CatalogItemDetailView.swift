import SwiftUI
import SwiftData

struct CatalogItemDetailView: View {
    @Bindable var item: CatalogItem

    @Environment(\.modelContext) private var modelContext
    @State private var justAdded: CollectionStatus?

    /// Swap for an injected instance in tests; the shared one carries the cache.
    private let pricing = PricingService.shared
    @State private var guide: PriceGuide?
    @State private var isRefreshingPrices = false

    private var ownedEntries: [CollectionItem] {
        item.collectionEntries.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                header
                actionButtons

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .readableContentColumn()
                }

                cardGrid

                if !ownedEntries.isEmpty {
                    DetailCard(title: "In Your Collection", systemImage: "tray.full") {
                        ForEach(ownedEntries) { entry in
                            NavigationLink(value: entry) {
                                CollectionItemRow(item: entry)
                            }
                            .buttonStyle(.plain)
                            if entry.id != ownedEntries.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(LayoutMetrics.screenEdgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.slug) {
            guide = await pricing.priceGuide(for: item)
        }
        .navigationTitle(item.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    addEntry(status: .owned)
                } label: {
                    Label("Add to Collection", systemImage: "plus")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 6) {
                ItemThumbnail(
                    kind: item.kind,
                    platformSymbol: item.platform?.iconSystemName,
                    imageName: item.imageName,
                    imageURL: item.imageURL,
                    size: 132, cornerRadius: 16,
                    contentMode: .fit
                )
                if let attribution = item.imageAttribution {
                    Text(attribution)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 132)
                        .multilineTextAlignment(.center)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.displayTitle).font(.title2.weight(.bold))
                HStack(spacing: 8) {
                    KindTag(kind: item.kind)
                    if let platform = item.platform {
                        Text("·")
                        NavigationLink(value: platform) { Text(platform.name) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }
                }
                .font(.callout)

                if let year = item.releaseYearNA {
                    KeyValueRow("Released (US)", String(year))
                }
                if let pub = item.manufacturerOrPublisher {
                    KeyValueRow(item.kind == .game ? "Publisher" : "Manufacturer", pub)
                }
                if let dev = item.developer { KeyValueRow("Developer", dev) }
                if let genre = item.genre { KeyValueRow("Genre", genre) }
            }
            .frame(maxWidth: 420, alignment: .leading)
            Spacer()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                addEntry(status: .owned)
            } label: {
                Label(item.isOwned ? "Add Another Copy" : "Add to Collection",
                      systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                addEntry(status: .wishlist)
            } label: {
                Label("Wishlist", systemImage: "star")
            }
            .buttonStyle(.bordered)
            .disabled(item.isWishlisted)

            if let justAdded {
                Label("Added to \(justAdded.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer()
        }
    }

    private var cardGrid: some View {
        let columns: [GridItem] = {
            #if os(macOS)
            [GridItem(.flexible(), spacing: LayoutMetrics.cardSpacing),
             GridItem(.flexible(), spacing: LayoutMetrics.cardSpacing)]
            #else
            [GridItem(.flexible())]
            #endif
        }()

        return LazyVGrid(columns: columns, alignment: .leading, spacing: LayoutMetrics.cardSpacing) {
            MarketValueCard(
                item: item,
                guide: guide,
                isRefreshing: isRefreshingPrices,
                hasLiveProvider: pricing.hasLiveProvider,
                onRefresh: refreshPrices
            )
            DetailCard(title: "Identifiers", systemImage: "barcode") {
                KeyValueRow("Catalog slug", item.slug)
                KeyValueRow("UPC", item.upc ?? "—")
                if let variant = item.variant {
                    KeyValueRow("Variant", variant)
                }
            }
        }
    }

    private func refreshPrices() {
        guard !isRefreshingPrices else { return }
        isRefreshingPrices = true
        Task {
            guide = await pricing.refresh(item, in: modelContext)
            isRefreshingPrices = false
        }
    }

    private func addEntry(status: CollectionStatus) {
        let entry = CollectionItem(
            catalogItem: item,
            status: status,
            condition: status == .owned ? .good : nil,
            completeness: status == .owned ? .loose : nil,
            playStatus: item.kind == .game && status == .owned ? .backlog : nil
        )
        modelContext.insert(entry)
        try? modelContext.save()
        withAnimation { justAdded = status }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { justAdded = nil }
        }
    }
}

// MARK: - Market value card

private struct MarketValueCard: View {
    var item: CatalogItem
    var guide: PriceGuide?
    var isRefreshing: Bool
    var hasLiveProvider: Bool
    var onRefresh: () -> Void

    /// Prefer the freshly resolved guide; fall back to the model's cached fields.
    private func value(_ condition: MarketCondition) -> Decimal? {
        if let v = guide?.value(for: condition) { return v }
        switch condition {
        case .loose: return item.estimatedValueLoose
        case .completeInBox: return item.estimatedValueComplete
        case .new: return item.estimatedValueSealed
        case .graded: return item.estimatedValueGraded
        default: return nil
        }
    }

    private var sourceName: String {
        guide?.primaryProvider.displayName ?? item.priceGuideSourceName ?? "Built-in Guide"
    }

    private var asOf: Date? { guide?.asOf ?? item.priceGuideUpdatedAt }
    private var salesVolume: Int? { guide?.salesVolumeYearly ?? item.salesVolumeYearly }

    var body: some View {
        DetailCard(title: "Market Value", systemImage: "dollarsign.circle") {
            ForEach(MarketCondition.primary) { condition in
                if let v = value(condition) {
                    KeyValueRow(condition.displayName, Money.string(v))
                }
            }

            if value(.loose) == nil && value(.completeInBox) == nil
                && value(.new) == nil && value(.graded) == nil {
                Text("No pricing yet for this item.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 6) {
                Text("Source: \(sourceName)")
                if let asOf {
                    Text("· as of \(asOf.mediumDateString)")
                }
                Spacer()
                if let salesVolume {
                    Label("\(salesVolume)/yr sold", systemImage: "chart.bar")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if let contributors = guide?.contributingProviders, contributors.count > 1 {
                Text("Also: " + contributors.dropFirst().map(\.displayName).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Button {
                onRefresh()
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing { ProgressView().controlSize(.small) }
                    Text(isRefreshing ? "Refreshing…" : "Refresh prices")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing)
            .padding(.top, 4)

            if !hasLiveProvider {
                Text("No live pricing provider configured — showing seed values. Add a PriceCharting token (or another adapter) to pull current prices.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let all = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    let item = all.first { $0.slug == "snes-chrono-trigger" } ?? all[0]
    NavigationStack {
        CatalogItemDetailView(item: item)
    }
    .modelContainer(container)
}
