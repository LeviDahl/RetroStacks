#if os(macOS)
import SwiftUI
import SwiftData

/// Poster-grid tile for the macOS system screen — the same information as
/// `PlatformCatalogRow` (an iOS list row), reshaped for a card wall instead of
/// a single stretched column. Visually matches `CatalogPosterCard` so the two
/// grids in the app (catalog browser, system drill-down) read as one language.
struct SystemCatalogTile: View {
    var catalogItem: CatalogItem
    var listStatus: CollectionStatus
    var onAdd: () -> Void
    var onToggleWishlist: (() -> Void)? = nil
    /// Right-click → Remove — the macOS-native equivalent of iOS's swipe action.
    var onRemove: (() -> Void)? = nil

    @State private var hovering = false

    private var entry: CollectionItem? { catalogItem.entry(for: listStatus) }
    private var wishlisted: Bool { catalogItem.entry(for: .wishlist) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationArea
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .contextMenu {
            if let onRemove, entry != nil {
                Button(role: .destructive, action: onRemove) {
                    Label(listStatus == .wishlist ? "Remove from Wishlist" : "Remove from Collection",
                          systemImage: "trash")
                }
            }
        }
    }

    /// Thumbnail + title + meta — the tappable-to-navigate part of the tile.
    /// Kept separate from `footer` so the Add/wishlist buttons there get their
    /// own tap targets instead of being swallowed by a tile-wide NavigationLink.
    private var navigationArea: some View {
        Group {
            if let entry {
                NavigationLink(value: entry) { navigationContent }
            } else {
                NavigationLink(value: catalogItem) { navigationContent }
            }
        }
        .buttonStyle(.plain)
    }

    private var navigationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ItemThumbnail(
                    kind: catalogItem.kind,
                    platformSymbol: catalogItem.platform?.iconSystemName,
                    imageName: catalogItem.imageName,
                    imageURL: catalogItem.imageURL,
                    size: 128, cornerRadius: 12, contentMode: .fit
                )
                .frame(maxWidth: .infinity)

                if entry != nil {
                    Image(systemName: listStatus == .wishlist ? "star.fill" : "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(listStatus == .wishlist ? Color.yellow : Color.green, in: Circle())
                        .padding(6)
                }
            }

            Text(catalogItem.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(catalogItem.kind.displayName)
                if let year = catalogItem.releaseYearNA { Text("·"); Text(String(year)) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let entry {
                CompletenessBadge(completeness: entry.completeness)
                if let value = entry.estimatedValue {
                    Text(Money.string(value))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help(listStatus == .wishlist ? "Add to wishlist" : "Add to collection")

                if let value = catalogItem.headlineValue {
                    Text(Money.string(value))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if let onToggleWishlist, hovering || wishlisted {
                Button(action: onToggleWishlist) {
                    Image(systemName: wishlisted ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(wishlisted ? .yellow : .secondary)
                .help(wishlisted ? "Remove from wishlist" : "Add to wishlist")
                .transition(.opacity)
            }
        }
    }
}

/// Grid tile shown while the screen is in multi-select ("Select") mode — a
/// checkmark badge in place of the Add button. Tiles already in the list are
/// locked, matching `SelectableCatalogRow` on iOS.
struct SelectableCatalogTile: View {
    var catalogItem: CatalogItem
    var alreadyIn: Bool
    var picked: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ItemThumbnail(
                        kind: catalogItem.kind,
                        platformSymbol: catalogItem.platform?.iconSystemName,
                        imageName: catalogItem.imageName,
                        imageURL: catalogItem.imageURL,
                        size: 128, cornerRadius: 12, contentMode: .fit
                    )
                    .frame(maxWidth: .infinity)

                    Image(systemName: (alreadyIn || picked) ? "checkmark.circle.fill" : "circle")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(
                            alreadyIn ? Color.green : picked ? Color.accentColor : Color.black.opacity(0.35),
                            in: Circle()
                        )
                        .padding(6)
                }

                Text(catalogItem.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(catalogItem.kind.displayName)
                    if let year = catalogItem.releaseYearNA { Text("·"); Text(String(year)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if alreadyIn {
                    Text("In list").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(alreadyIn ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(alreadyIn)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if picked {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let items = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    ScrollView {
        LazyVGrid(columns: LayoutMetrics.cardColumns(), spacing: LayoutMetrics.cardSpacing) {
            ForEach(items.prefix(8)) { item in
                SystemCatalogTile(catalogItem: item, listStatus: .owned, onAdd: {}, onToggleWishlist: {})
            }
        }
        .padding()
    }
    .modelContainer(container)
}
#endif
