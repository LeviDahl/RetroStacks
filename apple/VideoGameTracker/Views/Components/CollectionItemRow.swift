import SwiftUI
import SwiftData

/// One row in the compact (iOS / list) presentation of the collection.
struct CollectionItemRow: View {
    var item: CollectionItem

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(
                kind: item.kind,
                platformSymbol: item.catalogItem?.platform?.iconSystemName,
                imageName: item.catalogItem?.imageName,
                imageURL: item.catalogItem?.imageURL
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.platformShortName)
                    Text("·")
                    Text(item.kind.displayName)
                    if let year = item.catalogItem?.releaseYearNA {
                        Text("·")
                        Text(String(year))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: 6) {
                    CompletenessBadge(completeness: item.completeness)
                    ConditionLabel(condition: item.condition, compact: true)
                    if item.status != .owned {
                        StatusBadge(status: item.status)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.string(item.estimatedValue))
                    .font(.callout.weight(.semibold))
                if let delta = item.valueDelta, delta != 0 {
                    Text(Money.signedString(delta))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(delta < 0 ? .red : .green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let items = try! container.mainContext.fetch(FetchDescriptor<CollectionItem>())
    return List(items) { CollectionItemRow(item: $0) }
        .modelContainer(container)
}
