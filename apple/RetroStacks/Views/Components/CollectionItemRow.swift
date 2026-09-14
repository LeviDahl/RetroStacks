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
            .accessibilityHidden(true) // decorative — the title text beside it says the same thing

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
                .foregroundStyle(.mutedText)
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
                        .foregroundStyle(delta < 0 ? .accentRed : .accentGreen)
                }
            }
        }
        .padding(.vertical, 4)
        // One coherent sentence per row instead of VoiceOver stopping on every
        // Text/"·" separately — this is also what determines swipe order, and
        // it already matches the visual reading order above.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    // #Preview only, fixture data is always valid.
    // swiftlint:disable:next force_try
    let items = try! container.mainContext.fetch(FetchDescriptor<CollectionItem>())
    List(items) { CollectionItemRow(item: $0) }
        .modelContainer(container)
}
