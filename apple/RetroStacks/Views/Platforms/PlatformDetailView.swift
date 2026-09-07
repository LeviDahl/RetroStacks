import SwiftUI
import SwiftData

struct PlatformDetailView: View {
    @Bindable var platform: Platform

    @State private var kind: ItemKind = .console

    private var items: [CatalogItem] {
        platform.items(of: kind)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                header
                factGrid

                Picker("Kind", selection: $kind) {
                    ForEach(ItemKind.allCases) { k in
                        Text("\(k.pluralName) (\(platform.items(of: k).count))").tag(k)
                    }
                }
                .pickerStyle(.segmented)

                itemGrid
            }
            .padding(LayoutMetrics.screenEdgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(platform.shortName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The platform's primary console model, preferring one that has a photo.
    private var heroConsole: CatalogItem? {
        platform.consoles.first { $0.imageURL != nil } ?? platform.consoles.first
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            if let heroConsole, heroConsole.imageURL != nil {
                ItemThumbnail(
                    kind: .console,
                    platformSymbol: platform.iconSystemName,
                    imageURL: heroConsole.imageURL,
                    size: 96, cornerRadius: 18,
                    contentMode: .fit
                )
            } else {
                Image(systemName: platform.iconSystemName)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(width: 96, height: 96)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(platform.name).font(.title2.weight(.bold))
                Text("\(platform.manufacturer) · \(platform.eraLabel)")
                    .font(.callout).foregroundStyle(.secondary)
                Text(platform.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(platform.regionsAvailable) { region in
                        Text("\(region.flagSymbol) \(region.displayName)")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            Spacer()
        }
    }

    private var factGrid: some View {
        let columns: [GridItem] = {
            #if os(macOS)
            [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            #else
            [GridItem(.flexible()), GridItem(.flexible())]
            #endif
        }()
        return LazyVGrid(columns: columns, spacing: LayoutMetrics.cardSpacing) {
            FactTile(label: "US Launch", value: platform.releaseYearNA.map(String.init) ?? "—")
            FactTile(label: "Discontinued", value: platform.discontinuedYearNA.map(String.init) ?? "—")
            FactTile(label: "Generation", value: "\(platform.generation)")
            FactTile(label: "Catalog Entries", value: "\(platform.catalogItems.count)")
            FactTile(label: "Owned", value: "\(ownedCount)")
            FactTile(label: "On Wishlist", value: "\(wishlistCount)")
        }
    }

    private var itemGrid: some View {
        LazyVGrid(columns: LayoutMetrics.posterColumns(), spacing: LayoutMetrics.cardSpacing) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    CatalogPosterCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ownedCount: Int {
        platform.catalogItems.filter { $0.isOwned }.count
    }
    private var wishlistCount: Int {
        platform.catalogItems.filter { $0.isWishlisted }.count
    }
}

private struct FactTile: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let all = try! container.mainContext.fetch(FetchDescriptor<Platform>())
    let platform = all.first { $0.slug == "snes" } ?? all[0]
    NavigationStack {
        PlatformDetailView(platform: platform)
    }
    .modelContainer(container)
}
