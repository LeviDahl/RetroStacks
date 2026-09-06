import SwiftUI
import SwiftData

/// Drill-down target of the system-first Collection view: every item you own
/// (or want) for one platform.
struct SystemGamesList: View {
    var platform: Platform
    var mode: CollectionSection.Mode
    var searchText: String = ""

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.dateAdded, order: .reverse) private var allItems: [CollectionItem]

    private var items: [CollectionItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allItems.filter { item in
            item.status == mode.status
                && item.catalogItem?.platform?.slug == platform.slug
                && (query.isEmpty
                    || item.title.lowercased().contains(query)
                    || item.notes.lowercased().contains(query))
        }
    }

    private var summary: CollectionStats.SystemSummary? {
        CollectionStatsBuilder.systemSummaries(from: allItems, status: mode.status)
            .first { $0.platformSlug == platform.slug }
    }

    var body: some View {
        List {
            if let summary {
                Section {
                    SystemSummaryStrip(summary: summary)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                }
            }
            Section {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        CollectionItemRow(item: item)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(items.count) \(items.count == 1 ? "item" : "items")")
            }
        }
        .navigationTitle(platform.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: mode.status.symbol,
                    description: Text("No \(mode.status.displayName.lowercased()) items on \(platform.shortName).")
                )
            }
        }
    }

    private func delete(_ item: CollectionItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let platform = try! container.mainContext.fetch(FetchDescriptor<Platform>())
        .first { $0.slug == "snes" }!
    return NavigationStack {
        SystemGamesList(platform: platform, mode: .collection)
            .navigationDestination(for: CollectionItem.self) { CollectionItemDetailView(item: $0) }
            .navigationDestination(for: CatalogItem.self) { CatalogItemDetailView(item: $0) }
    }
    .modelContainer(container)
}
