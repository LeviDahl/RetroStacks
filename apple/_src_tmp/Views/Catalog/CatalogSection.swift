import SwiftUI
import SwiftData

struct CatalogSection: View {
    /// Optional starting filter, e.g. when opened from a platform.
    var initialPlatformSlug: String? = nil
    var initialKind: ItemKind? = nil

    @Query(sort: [SortDescriptor(\CatalogItem.name)]) private var allItems: [CatalogItem]
    @Query(sort: \Platform.generation) private var platforms: [Platform]

    @State private var viewModel = CatalogBrowseViewModel()
    @State private var selectedID: PersistentIdentifier?

    private var items: [CatalogItem] { viewModel.apply(to: allItems) }
    private var selectedItem: CatalogItem? {
        guard let selectedID else { return nil }
        return allItems.first { $0.persistentModelID == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            contentColumn
                .navigationSplitViewColumnWidth(min: 360, ideal: 560, max: 900)
        } detail: {
            Group {
                if let selectedItem {
                    CatalogItemDetailView(item: selectedItem)
                } else {
                    EmptyStateView(
                        title: "Browse the Catalog",
                        message: "Reference data for consoles, games, and accessories. Select an entry to see details and add it to your collection.",
                        systemImage: "books.vertical"
                    )
                }
            }
            .gameTrackerDestinations()
        }
        .navigationTitle("Catalog")
        .searchable(text: $viewModel.searchText, prompt: "Search consoles, games, accessories")
        .toolbar { toolbarContent }
        .onAppear {
            if let initialPlatformSlug { viewModel.platformSlugFilter = initialPlatformSlug }
            if let initialKind { viewModel.kindFilter = initialKind }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        if items.isEmpty {
            EmptyStateView(
                title: "No Matches",
                message: "Nothing in the catalog matches your filters.",
                systemImage: "magnifyingglass",
                actionTitle: viewModel.hasActiveFilters ? "Clear Filters" : nil,
                action: viewModel.hasActiveFilters ? { viewModel.clearFilters() } : nil
            )
        } else {
            #if os(macOS)
            ScrollView {
                LazyVGrid(columns: LayoutMetrics.posterColumns(), spacing: LayoutMetrics.cardSpacing) {
                    ForEach(items) { item in
                        Button { selectedID = item.persistentModelID } label: {
                            CatalogPosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .overlay(selectionRing(for: item))
                    }
                }
                .padding(LayoutMetrics.screenEdgePadding)
            }
            #else
            List(selection: $selectedID) {
                ForEach(items) { item in
                    CatalogItemRow(item: item).tag(item.persistentModelID)
                }
            }
            .listStyle(.plain)
            #endif
        }
    }

    @ViewBuilder
    private func selectionRing(for item: CatalogItem) -> some View {
        if selectedID == item.persistentModelID {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.tint, lineWidth: 2)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Kind", selection: $viewModel.kindFilter) {
                Text("All").tag(ItemKind?.none)
                ForEach(ItemKind.allCases) { Label($0.pluralName, systemImage: $0.symbol).tag(ItemKind?.some($0)) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Menu {
                Picker("Platform", selection: $viewModel.platformSlugFilter) {
                    Text("All Platforms").tag(String?.none)
                    ForEach(platforms) { Text($0.shortName).tag(String?.some($0.slug)) }
                }
                Picker("Ownership", selection: $viewModel.ownershipFilter) {
                    ForEach(CatalogBrowseViewModel.OwnershipFilter.allCases) {
                        Text($0.label).tag($0)
                    }
                }
                Divider()
                Picker("Sort By", selection: $viewModel.sortField) {
                    ForEach(CatalogBrowseViewModel.SortField.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Ascending", isOn: $viewModel.sortAscending)
                if viewModel.hasActiveFilters {
                    Divider()
                    Button("Clear Filters", role: .destructive) { viewModel.clearFilters() }
                }
            } label: {
                Label("Filter & Sort", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}

#Preview {
    NavigationStack {
        CatalogSection()
    }
    .modelContainer(SampleData.previewContainer())
}
