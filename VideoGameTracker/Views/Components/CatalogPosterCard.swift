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
                size: 128,
                cornerRadius: 12
            )
            .frame(maxWidth: .infinity)
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
    }

    @ViewBuilder
    private var ownershipBadge: some View {
        if item.isOwned {
            badge(symbol: "checkmark.seal.fill", color: .green)
        } else if item.isWishlisted {
            badge(symbol: "star.fill", color: .yellow)
        }
    }

    private func badge(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(5)
            .background(color, in: Circle())
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let items = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            ForEach(items.prefix(9).map { $0 }) { CatalogPosterCard(item: $0) }
        }
        .padding()
    }
    .modelContainer(container)
}
