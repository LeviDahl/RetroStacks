import SwiftUI
import SwiftData

struct CatalogSection: View {
    /// Optional starting filter, e.g. when opened from a platform.
    var initialPlatformSlug: String?
    var initialKind: ItemKind?

    @Query(sort: [SortDescriptor(\CatalogItem.name)]) private var allItems: [CatalogItem]
    @Query(sort: \Platform.generation) private var platforms: [Platform]

    @State private var viewModel = CatalogBrowseViewModel()
    @State private var selectedID: PersistentIdentifier?
    @State private var account = AccountService.shared
    @State private var isShowingCustomEntrySheet = false

    /// `viewModel.apply(to: allItems)` filters/sorts up to ~13,150 items —
    /// same bug class as `SystemGamesList.cachedCatalog` (see its doc
    /// comment): as a plain computed property this re-ran on *every* body
    /// evaluation, including ones with nothing to do with this screen's own
    /// filters (`allItems` is an unscoped `@Query`, so any `CatalogItem`
    /// change anywhere fires it). Cached here, refreshed only via
    /// `.task(id:)` on real filter/sort/search changes. Same accepted
    /// tradeoff as `SystemGamesList`: `ownershipFilter` won't live-reorder
    /// as collection entries change elsewhere — it re-filters on the next
    /// real dependency change instead of watching `CollectionItem` too.
    @State private var cachedItems: [CatalogItem] = []

    private var itemsCacheKey: String {
        "\(viewModel.kindFilter?.rawValue ?? "-")|\(viewModel.platformSlugFilter ?? "-")|"
            + "\(viewModel.generationFilter.map(String.init) ?? "-")|\(viewModel.ownershipFilter.rawValue)|"
            + "\(viewModel.searchText)|\(viewModel.sortField.rawValue)|\(viewModel.sortAscending)"
    }

    private var items: [CatalogItem] { cachedItems }
    private var selectedItem: CatalogItem? {
        guard let selectedID else { return nil }
        return allItems.first { $0.persistentModelID == selectedID }
    }

    private var navigationTitleText: String {
        guard let slug = viewModel.platformSlugFilter,
              let platform = platforms.first(where: { $0.slug == slug }) else { return "Catalog" }
        return platform.shortName
    }

    var body: some View {
        NavigationSplitView {
            // `.navigationTitle` lives here, not on the outer NavigationSplitView:
            // found live 2026-09-14 that on iOS-compact, where the split view
            // collapses to a single column, a title set on the *outer*
            // NavigationSplitView never reaches the navigation bar (confirmed via
            // a raw accessibility-hierarchy dump — the bar's only child was a
            // blank-label StaticText). `CollectionSection`'s plain NavigationStack
            // doesn't have this problem since there's no collapse behavior to lose
            // the title across. Setting it on the visible *column* instead is what
            // actually propagates in both the collapsed and split layouts.
            contentColumn
                .navigationSplitViewColumnWidth(min: 360, ideal: 560, max: 900)
                .navigationTitle(navigationTitleText)
                .searchable(
                    text: $viewModel.searchText,
                    prompt: viewModel.platformSlugFilter == nil ? "Search the whole catalog" : "Search \(navigationTitleText)"
                )
                .toolbar { toolbarContent }
                .task(id: itemsCacheKey) { cachedItems = viewModel.apply(to: allItems) }
                .sheet(isPresented: $isShowingCustomEntrySheet) {
                    CustomCatalogItemSheet(initialPlatformSlug: viewModel.platformSlugFilter)
                }
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
            .appNavigationDestinations()
        }
        .onAppear {
            if let initialPlatformSlug { viewModel.platformSlugFilter = initialPlatformSlug }
            if let initialKind { viewModel.kindFilter = initialKind }
            // Seed synchronously, same frame as the filters above — arriving
            // here already filtered (e.g. a platform tapped from Dashboard)
            // would otherwise show a one-frame "No Matches" flash before
            // `.task(id:)` catches up (it starts a beat after `onAppear`).
            cachedItems = viewModel.apply(to: allItems)
        }
    }

    /// Browsing by system is the default landing view — at ~3,600 catalog
    /// entries and growing, a flat list of everything doesn't scale as a
    /// starting point. As soon as the user touches any filter or search
    /// (`hasActiveFilters`), this steps aside for the existing flat/filtered
    /// list below, which already handles every combination correctly —
    /// picking a platform here just sets `platformSlugFilter`, the same
    /// field the toolbar's own Platform picker already used.
    @ViewBuilder
    private var contentColumn: some View {
        if !viewModel.hasActiveFilters {
            platformList
        } else if items.isEmpty {
            EmptyStateView(
                title: "No Matches",
                message: "Nothing in the catalog matches your filters.",
                systemImage: "magnifyingglass",
                actionTitle: "Clear Filters",
                action: { viewModel.clearFilters() }
            )
        } else {
            filteredList
        }
    }

    private var platformList: some View {
        List(platforms) { platform in
            Button {
                viewModel.platformSlugFilter = platform.slug
            } label: {
                CatalogPlatformRow(platform: platform)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var filteredList: some View {
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

    @ViewBuilder
    private func selectionRing(for item: CatalogItem) -> some View {
        if selectedID == item.persistentModelID {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.tint, lineWidth: 2)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.platformSlugFilter != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    viewModel.platformSlugFilter = nil
                    viewModel.searchText = ""
                } label: {
                    Label("All Systems", systemImage: "chevron.left")
                }
            }
        }
        // Grouped explicitly (not three bare `ToolbarItem`s) so macOS lays
        // these out as one coherent control cluster instead of improvising a
        // shared glass capsule around whatever happens to be adjacent — found
        // live 2026-09-17: three separate `ToolbarItem`s here rendered with
        // their tops visibly clipped inside a shared pill background.
        ToolbarItemGroup {
            Button {
                isShowingCustomEntrySheet = true
            } label: {
                Label("Add Custom Entry", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .disabled(!account.state.isSignedIn)
            .help(
                account.state.isSignedIn
                    ? "Add a game the catalog is missing, or a bootleg/variant just for you."
                    : "Sign in to add a custom catalog entry."
            )
            Picker("Kind", selection: $viewModel.kindFilter) {
                Text("All").tag(ItemKind?.none)
                ForEach(ItemKind.allCases) { Label($0.pluralName, systemImage: $0.symbol).tag(ItemKind?.some($0)) }
            }
            .pickerStyle(.menu)
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
