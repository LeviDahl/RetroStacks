import SwiftUI
import SwiftData

struct CatalogItemRow: View {
    var item: CatalogItem
    var showPlatform: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(
                kind: item.kind,
                platformSymbol: item.platform?.iconSystemName,
                imageName: item.imageName,
                imageURL: item.imageURL
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if showPlatform { Text(item.platformShortName); Text("·") }
                    Text(item.kind.displayName)
                    if let year = item.releaseYearNA { Text("·"); Text(String(year)) }
                    if let publisher = item.manufacturerOrPublisher {
                        Text("·"); Text(publisher).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let value = item.headlineValue {
                    Text(Money.string(value))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    if item.isOwned {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    if item.isWishlisted {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let items = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    return List(items.prefix(12).map { $0 }) { CatalogItemRow(item: $0) }
        .modelContainer(container)
}
