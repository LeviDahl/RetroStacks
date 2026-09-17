import SwiftUI
import SwiftData

// Split out of SystemGamesList.swift 2026-09-17 (file_length): the row/tile/
// scrubber views used by SystemGamesList's list and grid layouts, but fully
// self-contained — none of them reference SystemGamesList's own private
// state, so this split needed no access-level changes anywhere.

// MARK: - iOS row

/// Thumbnail + title + meta line — the shared visual for every catalog row in
/// the drill-down (plain, selectable, hover).
struct CatalogRowContent: View {
    var catalogItem: CatalogItem

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(
                kind: catalogItem.kind,
                platformSymbol: catalogItem.platform?.iconSystemName,
                imageName: catalogItem.imageName,
                imageURL: catalogItem.imageURL,
                size: 48, cornerRadius: 10
            )
            .accessibilityHidden(true) // decorative — the title text beside it says the same thing
            VStack(alignment: .leading, spacing: 3) {
                Text(catalogItem.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(catalogItem.kind.displayName)
                    if let year = catalogItem.releaseYearNA { Text("·"); Text(String(year)) }
                    if let pub = catalogItem.manufacturerOrPublisher { Text("·"); Text(pub).lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.mutedText)
                .lineLimit(1)
            }
        }
    }
}

/// A catalog row inside a platform drill-down: title + meta on the left,
/// ownership state or a one-tap Add on the right. On macOS a wishlist toggle
/// appears on hover.
struct PlatformCatalogRow: View {
    var catalogItem: CatalogItem
    var listStatus: CollectionStatus
    var onAdd: () -> Void
    var onToggleWishlist: (() -> Void)?

    @State private var hovering = false

    private var entry: CollectionItem? { catalogItem.entry(for: listStatus) }
    private var wishlisted: Bool { catalogItem.entry(for: .wishlist) != nil }

    /// On iOS there's no hover state, so gating on `hovering` (macOS-only)
    /// left the *only* way to add a not-yet-wishlisted item to the wishlist
    /// from this row an undiscoverable leading swipe — the button only ever
    /// appeared once an item was already wishlisted. Persistent on iOS;
    /// still hover-revealed on macOS, where it's genuinely just decluttering
    /// a denser layout, not hiding the only way in.
    private var wishlistButtonVisible: Bool {
        #if os(iOS)
        true
        #else
        hovering || wishlisted
        #endif
    }

    var body: some View {
        HStack(spacing: 12) {
            if let entry {
                NavigationLink(value: entry) { CatalogRowContent(catalogItem: catalogItem) }
                    .buttonStyle(.plain)
            } else {
                NavigationLink(value: catalogItem) { CatalogRowContent(catalogItem: catalogItem) }
                    .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if let onToggleWishlist, wishlistButtonVisible {
                Button(action: onToggleWishlist) {
                    Image(systemName: wishlisted ? "star.fill" : "star")
                        .foregroundStyle(wishlisted ? .accentGold : .secondary)
                }
                .buttonStyle(.borderless)
                .help(wishlisted ? "Remove from wishlist" : "Add to wishlist")
                .accessibilityLabel(wishlisted ? "Remove from wishlist" : "Add to wishlist")
                .transition(.opacity)
            }

            trailing
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        #endif
        .swipeActions(edge: .leading) {
            if let onToggleWishlist {
                Button(action: onToggleWishlist) {
                    Label(wishlisted ? "Unwish" : "Wishlist",
                          systemImage: wishlisted ? "star.slash" : "star")
                }
                // Fixed, not `.accentGold` — this is a fill with the
                // system's own white label drawn on top, not text-on-wash,
                // so it needs to stay dark enough for white-on-top contrast
                // in *both* appearances, not flip like `.accentGold` does.
                .tint(Color(red: 0.471, green: 0.337, blue: 0.0))
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let entry {
            VStack(alignment: .trailing, spacing: 3) {
                if let value = entry.estimatedValue {
                    Text(Money.string(value)).font(.callout.weight(.semibold)).foregroundStyle(.mutedText)
                }
                HStack(spacing: 5) {
                    CompletenessBadge(completeness: entry.completeness)
                    Image(systemName: listStatus == .wishlist ? "star.fill" : "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(listStatus == .wishlist ? .accentGold : .accentGreen)
                        .accessibilityLabel(listStatus == .wishlist ? "Wishlisted" : "Owned")
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            .help(listStatus == .wishlist ? "Add to wishlist" : "Add to collection")
            .accessibilityLabel(listStatus == .wishlist ? "Add to wishlist" : "Add to collection")
        }
    }
}

/// Row shown while the list is in multi-select ("Select") mode: a checkbox in
/// place of the disclosure / add button. Rows already in the list are locked.
struct SelectableCatalogRow: View {
    var catalogItem: CatalogItem
    var alreadyIn: Bool
    var picked: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: alreadyIn ? "checkmark.circle.fill"
                      : picked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(alreadyIn ? .accentGreen : picked ? Color.accentColor : .secondary)
                CatalogRowContent(catalogItem: catalogItem)
                Spacer(minLength: 8)
                if alreadyIn {
                    Text("In list").font(.caption).foregroundStyle(.mutedText)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyIn)
    }
}

// MARK: - A–Z scrubber

/// Trailing-edge letter index for long, title-sorted catalogs. Tap or drag a
/// letter to jump. iOS only — macOS has a real scrollbar and more room.
struct AZScrubber: View {
    var letters: [String]
    var onSelect: (String) -> Void

    @State private var active: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active == letter ? Color.white : Color.accentColor)
                    .frame(width: 16, height: 15)
                    .background {
                        if active == letter {
                            Circle().fill(Color.accentColor)
                        }
                    }
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let count = letters.count
                    guard count > 0 else { return }
                    let rowH: CGFloat = 16
                    let idx = min(max(Int(value.location.y / rowH), 0), count - 1)
                    let letter = letters[idx]
                    if letter != active {
                        active = letter
                        onSelect(letter)
                    }
                }
                .onEnded { _ in active = nil }
        )
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel("Section index")
    }
}

// MARK: - Summary strip

/// Compact count / completion / value strip reused at the top of a system's list.
struct SystemSummaryStrip: View {
    var summary: CollectionStats.SystemSummary

    var body: some View {
        HStack(spacing: 0) {
            metric("Owned",
                   summary.catalogGameCount > 0
                     ? "\(summary.ownedGameCount)/\(summary.catalogGameCount)"
                     : "\(summary.ownedItemCount)")
            Divider().frame(height: 34)
            metric("Complete", summary.catalogGameCount > 0 ? "\(summary.completionPercent)%" : "—")
            Divider().frame(height: 34)
            metric("Value", Money.string(summary.value))
            if summary.remainingValue > 0 {
                Divider().frame(height: 34)
                metric("To finish", Money.string(summary.remainingValue))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.mutedText)
        }
        .frame(maxWidth: .infinity)
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
    NavigationStack {
        SystemGamesList(platform: platform, mode: .collection)
            .navigationDestination(for: CollectionItem.self) { CollectionItemDetailView(item: $0) }
            .navigationDestination(for: CatalogItem.self) { CatalogItemDetailView(item: $0) }
    }
    .modelContainer(container)
}
