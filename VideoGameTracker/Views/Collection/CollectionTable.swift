import SwiftUI
import SwiftData

/// Dense, desktop-style table for the collection. Only used where
/// `LayoutMetrics.usesTableForLists` is true (macOS today).
struct CollectionTable: View {
    var items: [CollectionItem]
    @Binding var selection: PersistentIdentifier?

    var body: some View {
        Table(items, selection: $selection) {
            TableColumn("Title") { item in
                HStack(spacing: 10) {
                    ItemThumbnail(
                        kind: item.kind,
                        platformSymbol: item.catalogItem?.platform?.iconSystemName,
                        imageName: item.catalogItem?.imageName,
                        size: 34, cornerRadius: 7
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).lineLimit(1)
                        if let genre = item.catalogItem?.genre {
                            Text(genre).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 200, ideal: 280)

            TableColumn("Platform") { Text($0.platformShortName) }
                .width(min: 60, ideal: 80)

            TableColumn("Kind") { KindTag(kind: $0.kind) }
                .width(min: 90, ideal: 110)

            TableColumn("Completeness") { CompletenessBadge(completeness: $0.completeness) }
                .width(min: 90, ideal: 110)

            TableColumn("Condition") { ConditionLabel(condition: $0.condition) }
                .width(min: 90, ideal: 110)

            TableColumn("Paid") { Text(Money.string($0.pricePaid)).monospacedDigit() }
                .width(min: 60, ideal: 80)

            TableColumn("Est. Value") { item in
                Text(Money.string(item.estimatedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Δ") { item in
                if let delta = item.valueDelta, delta != 0 {
                    Text(Money.signedString(delta))
                        .monospacedDigit()
                        .foregroundStyle(delta < 0 ? .red : .green)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("Added") { item in
                Text(item.dateAdded.mediumDateString)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
    }
}
