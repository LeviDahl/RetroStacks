import SwiftUI
import SwiftData

/// The user's collection (or wishlist). Defaults to a **system-first** view —
/// a list of consoles you drill into — with an **All Games** toggle for a flat
/// view across every platform. Single `NavigationStack`: the list is the focus
/// and nothing about it collapses; item detail is a push.
struct CollectionSection: View {
    enum Mode: Hashable {
        case collection, wishlist

        var title: String {
            switch self {
            case .collection: "My Collection"
            case .wishlist: "Wishlist"
            }
        }
        var status: CollectionStatus {
            switch self {
            case .collection: .owned
            case .wishlist: .wishlist
            }
        }
    }

    var mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.dateAdded, order: .reverse) private var allItems: [CollectionItem]
    @Query(sort: \Platform.generation) private var platforms: [Platform]

    @State private var viewModel = CollectionListViewModel()
    @State private var path = NavigationPath()
    @State private var showingCatalogPicker = false

    /// Persisted per install. Default: drill into each system.
    @AppStorage("collection.groupBySystem") private var groupBySystem = true

    private var flatItems: [CollectionItem] {
        viewModel.apply(to: allItems)
    }

    private var summaries: [CollectionStats.SystemSummary] {
        var list = CollectionStatsBuilder.systemSummaries(from: allItems, status: mode.status)
        let q = viewModel.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.platformName.lowercased().contains(q)
                    || $0.platformShortName.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            .navigationTitle(mode.title)
            .navigationDestination(for: Platform.self) { platform in
                SystemGamesList(platform: platform, mode: mode, searchText: viewModel.searchText)
            }
            .navigationDestination(for: CollectionItem.self) { CollectionItemDetailView(item: $0) }
            .navigationDestination(for: CatalogItem.self) { CatalogItemDetailView(item: $0) }
            .toolbar { toolbarContent }
            .searchable(text: $viewModel.searchText,
                        prompt: groupBySystem ? "Search systems" : "Search \(mode.title.lowercased())")
            .sheet(isPresented: $showingCatalogPicker) {
                AddToCollectionFlow(defaultStatus: mode.status)
            }
        }
        .onAppear { viewModel.statusFilter = mode.status }
    }

    // MARK: Header (grouping toggle + collection totals)

    private var header: some View {
        VStack(spacing: 10) {
            Picker("Grouping", selection: $groupBySystem) {
                Text("By System").tag(true)
                Text("All Games").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                let systemCount = summaries.count
                let itemCount = summaries.reduce(0) { $0 + $1.ownedItemCount }
                let value = summaries.reduce(Decimal(0)) { $0 + $1.value }
                Text("\(systemCount) system\(systemCount == 1 ? "" : "s")")
                Text("·")
                Text("\(itemCount) \(mode == .wishlist ? "wanted" : "item\(itemCount == 1 ? "" : "s")")")
                if mode == .collection && value > 0 {
                    Text("·")
                    Text(Money.string(value))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if allItems.filter({ $0.status == mode.status }).isEmpty {
            emptyState
        } else if groupBySystem {
            systemsList
        } else {
            allGamesList
        }
    }

    private var systemsList: some View {
        List {
            ForEach(summaries) { summary in
                if let platform = platforms.first(where: { $0.slug == summary.platformSlug }) {
                    NavigationLink(value: platform) {
                        SystemCollectionRow(summary: summary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    @ViewBuilder
    private var allGamesList: some View {
        if LayoutMetrics.usesTableForLists {
            CollectionTable(items: flatItems) { path.append($0) }
                .overlay(alignment: .bottom) { filterSummaryBar }
        } else {
            List {
                ForEach(flatItems) { item in
                    NavigationLink(value: item) {
                        CollectionItemRow(item: item)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay(alignment: .bottom) { filterSummaryBar }
        }
    }

    // MARK: Empty / filter chrome

    @ViewBuilder
    private var emptyState: some View {
        EmptyStateView(
            title: mode == .wishlist ? "Wishlist Is Empty" : "No Items Yet",
            message: mode == .wishlist
                ? "Add catalog items you're hunting for and track them here."
                : "Add a console, game, or accessory from the catalog to start your collection.",
            systemImage: mode.status.symbol,
            actionTitle: "Add from Catalog",
            action: { showingCatalogPicker = true }
        )
    }

    @ViewBuilder
    private var filterSummaryBar: some View {
        if viewModel.kindFilter != nil {
            HStack(spacing: 8) {
                if let kind = viewModel.kindFilter {
                    FilterChip(text: kind.pluralName) { viewModel.kindFilter = nil }
                }
                Spacer()
                Text("\(flatItems.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !groupBySystem {
            ToolbarItem {
                Menu {
                    Picker("Kind", selection: $viewModel.kindFilter) {
                        Text("All Kinds").tag(ItemKind?.none)
                        ForEach(ItemKind.allCases) { Text($0.pluralName).tag(ItemKind?.some($0)) }
                    }
                    Divider()
                    Picker("Sort By", selection: $viewModel.sortField) {
                        ForEach(CollectionListViewModel.SortField.allCases) {
                            Text($0.label).tag($0)
                        }
                    }
                    Toggle("Ascending", isOn: $viewModel.sortAscending)
                } label: {
                    Label("Filter & Sort", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        ToolbarItem {
            Button {
                showingCatalogPicker = true
            } label: {
                Label("Add Item", systemImage: "plus")
            }
        }
    }

    // MARK: Actions

    private func delete(_ item: CollectionItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

private struct FilterChip: View {
    var text: String
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.caption.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.tint.opacity(0.15), in: Capsule())
    }
}

#Preview("Collection") {
    CollectionSection(mode: .collection)
        .modelContainer(SampleData.previewContainer())
}

#Preview("Wishlist") {
    CollectionSection(mode: .wishlist)
        .modelContainer(SampleData.previewContainer())
}
