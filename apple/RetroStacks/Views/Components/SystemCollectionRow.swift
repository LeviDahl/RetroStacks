import SwiftUI
import SwiftData

/// One console row in the system-first Collection view: icon, name, and a
/// count / completion / value strip with a completion bar. Modeled on the
/// per-system rows in Retro Game Collector.
struct SystemCollectionRow: View {
    var summary: CollectionStats.SystemSummary

    private var accent: Color { PlatformPalette.color(for: summary.platformSlug) }

    private var countText: String {
        summary.catalogGameCount > 0
            ? "\(summary.ownedGameCount)/\(summary.catalogGameCount)"
            : "\(summary.ownedItemCount) item\(summary.ownedItemCount == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            ItemThumbnail(
                kind: .console,
                platformSymbol: summary.iconSystemName,
                imageURL: summary.heroImageURL,
                size: 48,
                cornerRadius: 11,
                contentMode: .fit
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.platformName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(countText, systemImage: "gamecontroller")
                    if summary.catalogGameCount > 0 {
                        Label("\(summary.completionPercent)%", systemImage: "chart.pie")
                    }
                    Label(Money.string(summary.value), systemImage: "banknote")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                if summary.catalogGameCount > 0 {
                    ProgressView(value: summary.completionRatio)
                        .progressViewStyle(.linear)
                        .tint(accent)
                        .frame(maxWidth: 240)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(minHeight: 54)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let items = try! container.mainContext.fetch(FetchDescriptor<CollectionItem>())
    let summaries = CollectionStatsBuilder.systemSummaries(from: items, status: .owned)
    return List(summaries) { SystemCollectionRow(summary: $0) }
        .modelContainer(container)
}
