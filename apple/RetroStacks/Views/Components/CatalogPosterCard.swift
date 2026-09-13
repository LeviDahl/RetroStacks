import SwiftUI
import SwiftData

/// Grid cell used on macOS/iPad where there is room for a poster wall instead of
/// a single-column list.
struct CatalogPosterCard: View {
    var item: CatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemThumbnail(
                kind: item.kind,
                platformSymbol: item.platform?.iconSystemName,
                imageName: item.imageName,
                imageURL: item.imageURL,
                size: 128,
                cornerRadius: 12,
                contentMode: .fit
            )
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true) // decorative — the title text below says the same thing
            .overlay(alignment: .topTrailing) {
                ownershipBadge
                    .padding(6)
            }

            Text(item.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(item.platformShortName)
                if let year = item.releaseYearNA { Text("·"); Text(String(year)) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let value = item.headlineValue {
                Text(Money.string(value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var ownershipBadge: some View {
        // Fixed dark colors, not the adaptive accents — a white icon sits on
        // top of this fill (see `badge(...)` below), so it needs to stay
        // dark in both appearances, unlike text-on-wash uses.
        if item.isOwned {
            badge(symbol: "checkmark.seal.fill", color: Color(red: 0.118, green: 0.431, blue: 0.184), label: "Owned")
        } else if item.isWishlisted {
            badge(symbol: "star.fill", color: Color(red: 0.471, green: 0.337, blue: 0.0), label: "Wishlisted")
        }
    }

    private func badge(symbol: String, color: Color, label: String) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(5)
            .background(color, in: Circle())
            .accessibilityLabel(label)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let items = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            ForEach(items.prefix(9).map { $0 }) { CatalogPosterCard(item: $0) }
        }
        .padding()
    }
    .modelContainer(container)
}
