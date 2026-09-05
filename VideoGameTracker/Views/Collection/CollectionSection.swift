import SwiftUI
import SwiftData

/// List/table ↔ detail split for the user's collection. `mode` swaps between the
/// full collection and the wishlist-only view.
struct CollectionSection: View {
    enum Mode {
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
    @State private var selectedItemID: PersistentIdentifier?
    @State private var showingCatalogPicker = false

    private var items: [CollectionItem] {
        viewModel.apply(to: allItems)
    }

    private var selectedItem: CollectionItem? {
        guard let selectedItemID else { return nil }
        return allItems.first { $0.persistentModelID == selectedItemID }
    }

    var body: some View {
        NavigationSplitView {
            listColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 460, max: 720)
        } detail: {
            Group {
                if let selectedItem {
                    CollectionItemDetailView(item: selectedItem)
                } else {
                    EmptyStateView(
                        title: "Select an Item",
                        message: "Pick something on the left to see its condition, value history, and notes.",
                        systemImage: mode.status.symbol
                    )
                }
            }
            .gameTrackerDestinations()
        }
        .navigationTitle(mode.title)
        .onAppear { viewModel.statusFilter = mode.status }
        .searchable(text: $viewModel.searchText, prompt: "Search \(mode.title.lowercased())")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingCatalogPicker) {
            AddToCollectionFlow(defaultStatus: mode.status)
        }
    }

    // MARK: Columns

    @ViewBuilder
    private var listColumn: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else if LayoutMetrics.usesTableForLists {
                CollectionTable(items: items, selection: $selectedItemID)
            } else {
                List(selection: $selectedItemID) {
                    ForEach(items) { item in
                        CollectionItemRow(item: item)
                            .tag(item.persistentModelID)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { filterSummaryBar }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.hasActiveFilters {
            EmptyStateView(
                title: "No Matches",
                message: "No items match the current search and filters.",
                systemImage: "line.3.horizontal.decrease.circle",
                actionTitle: "Clear Filters",
                action: { viewModel.clearFilters() }
            )
        } else {
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
    }

    @ViewBuilder
    private var filterSummaryBar: some View {
        if viewModel.kindFilter != nil || viewModel.platformSlugFilter != nil {
            HStack(spacing: 8) {
                if let kind = viewModel.kindFilter {
                    FilterChip(text: kind.pluralName) { viewModel.kindFilter = nil }
                }
                if let slug = viewModel.platformSlugFilter,
                   let platform = platforms.first(where: { $0.slug == slug }) {
                    FilterChip(text: platform.shortName) { viewModel.platformSlugFilter = nil }
                }
                Spacer()
                Text("\(items.count) shown")
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
        ToolbarItem {
            Menu {
                Picker("Kind", selection: $viewModel.kindFilter) {
                    Text("All Kinds").tag(ItemKind?.none)
                    ForEach(ItemKind.allCases) { Text($0.pluralName).tag(ItemKind?.some($0)) }
                }
                Picker("Platform", selection: $viewModel.platformSlugFilter) {
                    Text("All Platforms").tag(String?.none)
                    ForEach(platforms) { Text($0.shortName).tag(String?.some($0.slug)) }
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
        if selectedItemID == item.persistentModelID { selectedItemID = nil }
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
    NavigationStack {
        CollectionSection(mode: .collection)
    }
    .modelContainer(SampleData.previewContainer())
}

#Preview("Wishlist") {
    NavigationStack {
        CollectionSection(mode: .wishlist)
    }
    .modelContainer(SampleData.previewContainer())
}
