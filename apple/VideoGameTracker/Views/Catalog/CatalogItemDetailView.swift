import SwiftUI
import SwiftData

struct CatalogItemDetailView: View {
    @Bindable var item: CatalogItem

    @Environment(\.modelContext) private var modelContext
    @State private var justAdded: CollectionStatus?

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
            DetailCard(title: "US Reference Prices", systemImage: "dollarsign.circle") {
                KeyValueRow("Loose", Money.string(item.estimatedValueLoose))
                KeyValueRow("Complete in Box", Money.string(item.estimatedValueComplete))
                KeyValueRow("Sealed", Money.string(item.estimatedValueSealed))
                Text("Placeholder values — live pricing arrives with the API.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            DetailCard(title: "Identifiers", systemImage: "barcode") {
                KeyValueRow("Catalog slug", item.slug)
                KeyValueRow("UPC", item.upc ?? "—")
                if let variant = item.variant {
                    KeyValueRow("Variant", variant)
                }
            }
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

#Preview {
    let container = SampleData.previewContainer()
    let all = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    let item = all.first { $0.slug == "snes-chrono-trigger" } ?? all[0]
    return NavigationStack {
        CatalogItemDetailView(item: item)
    }
    .modelContainer(container)
}
