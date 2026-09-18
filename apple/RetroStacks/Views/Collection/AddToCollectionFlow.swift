import SwiftUI
import SwiftData

/// Sheet: browse the catalog by system, pick an entry, and create a
/// `CollectionItem` for it.
///
/// System-first by default (a `Platform` list, same shape as
/// `CollectionSection`'s "By System" grouping) rather than one flat,
/// searchable list of every catalog item — at ~3,600 items today and growing,
/// scrolling/searching a single list of every game ever made doesn't scale.
/// Typing in the search field switches to a flat cross-platform result list
/// instead (for "I know exactly what I'm looking for"), so nothing is lost —
/// browsing by system is just the default instead of the only option.
struct AddToCollectionFlow: View {
    var defaultStatus: CollectionStatus

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Platform.generation) private var platforms: [Platform]
    @State private var searchText = ""
    @State private var account = AccountService.shared
    @State private var isShowingCustomEntrySheet = false
    #if os(iOS)
    @State private var showingScanner = false
    #endif
    /// Owned adds go through `QuickAddSheet` instead of a silent Loose/Good
    /// default — matches `SystemGamesList`'s `handleAdd`, so this sheet's
    /// three entry points (platform picker, flat search, barcode scanner —
    /// all three funnel through `add(_:)` below) behave the same way as
    /// every other "add as owned" path in the app now.
    @State private var quickAddTarget: CatalogItem?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    CatalogSearchResultsList(
                        searchText: searchText, status: defaultStatus, onAdd: add,
                        onAddCustom: { isShowingCustomEntrySheet = true }
                    )
                } else {
                    platformList
                }
            }
            .searchable(text: $searchText, prompt: "Search the whole catalog")
            .navigationTitle(defaultStatus == .wishlist ? "Add to Wishlist" : "Add to Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                #if os(iOS)
                ToolbarItem {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                }
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $showingScanner) {
                BarcodeScanScreen(onFound: add)
            }
            #endif
            .sheet(item: $quickAddTarget) { catalogItem in
                QuickAddSheet(catalogItem: catalogItem) { completeness, condition in
                    _ = CollectionActions.add(
                        catalogItem, status: .owned,
                        completeness: completeness, condition: condition,
                        in: modelContext
                    )
                    dismiss()
                }
            }
            .sheet(isPresented: $isShowingCustomEntrySheet) {
                CustomCatalogItemSheet(initialName: searchText, onCreated: add)
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    private var platformList: some View {
        List {
            ForEach(platforms) { platform in
                NavigationLink {
                    PlatformCatalogPicker(platform: platform, status: defaultStatus, onAdd: add)
                } label: {
                    CatalogPlatformRow(platform: platform)
                }
            }
            Section {
                addCustomEntryRow
            }
        }
        .listStyle(.inset)
    }

    /// "Can't find it?" — the whole point of this sheet is adding *something*
    /// to the collection, so a game the shared catalog is missing (a bootleg,
    /// an obscure homebrew, a variant) needs a way in right here, not just on
    /// the standalone Browse Catalog screen. Gated on sign-in like every
    /// other custom-entry entry point, since RLS only accepts an owned insert.
    private var addCustomEntryRow: some View {
        Button {
            isShowingCustomEntrySheet = true
        } label: {
            Label("Can't find it? Add a Custom Entry", systemImage: "plus.circle")
        }
        .disabled(!account.state.isSignedIn)
        .help(account.state.isSignedIn ? "" : "Sign in to add a custom catalog entry.")
    }

    private func add(_ item: CatalogItem) {
        if defaultStatus == .owned {
            quickAddTarget = item
        } else {
            CollectionActions.add(item, status: defaultStatus, in: modelContext)
            dismiss()
        }
    }
}

/// One row in the platform picker — icon, name, and how many catalog entries
/// it has, so it's clear there's actually something to browse into. Not
/// `private` — `CatalogSection` reuses it for the same "browse by system
/// first" default.
struct CatalogPlatformRow: View {
    var platform: Platform

    var body: some View {
        HStack(spacing: 14) {
            ItemThumbnail(
                kind: .console,
                platformSymbol: platform.iconSystemName,
                imageURL: platform.consoles.first?.imageURL,
                size: 44, cornerRadius: 10, contentMode: .fit
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name).font(.body.weight(.medium)).lineLimit(1)
                let count = platform.visibleCatalogItems().count
                Text("\(count) catalog \(count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.mutedText)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Drilled-into-one-platform picker: search/filter just that platform's
/// catalog instead of the whole thing.
private struct PlatformCatalogPicker: View {
    var platform: Platform
    var status: CollectionStatus
    var onAdd: (CatalogItem) -> Void

    @State private var searchText = ""
    @State private var kindFilter: ItemKind?

    private var results: [CatalogItem] {
        var items = platform.catalogItems
        if let kindFilter { items = items.filter { $0.kind == kindFilter } }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { items = items.filter { $0.name.lowercased().contains(q) } }
        return items.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Picker("Kind", selection: $kindFilter) {
                Text("All").tag(ItemKind?.none)
                ForEach(ItemKind.allCases) { Text($0.pluralName).tag(ItemKind?.some($0)) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(results) { item in
                Button { onAdd(item) } label: {
                    HStack {
                        CatalogItemRow(item: item, showPlatform: false)
                        if item.entry(for: status) != nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.mutedText)
                                .accessibilityLabel(status == .wishlist ? "Already on wishlist" : "Already in collection")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search \(platform.shortName)")
        .navigationTitle(platform.shortName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Flat, cross-platform results — what typing into the search field falls
/// back to, same shape the old always-flat list used.
private struct CatalogSearchResultsList: View {
    var searchText: String
    var status: CollectionStatus
    var onAdd: (CatalogItem) -> Void
    var onAddCustom: () -> Void

    @Query(sort: [SortDescriptor(\CatalogItem.name)]) private var catalog: [CatalogItem]
    @State private var account = AccountService.shared
    @State private var kindFilter: ItemKind?

    private var results: [CatalogItem] {
        var items = catalog
        if let kindFilter { items = items.filter { $0.kind == kindFilter } }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.name.lowercased().contains(q)
                    || $0.platformShortName.lowercased().contains(q)
            }
        }
        return items
    }

    private var grouped: [(platform: String, items: [CatalogItem])] {
        Dictionary(grouping: results) { $0.platformShortName }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.platform < $1.platform }
    }

    var body: some View {
        List {
            Picker("Kind", selection: $kindFilter) {
                Text("All").tag(ItemKind?.none)
                ForEach(ItemKind.allCases) { Text($0.pluralName).tag(ItemKind?.some($0)) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(grouped, id: \.platform) { group in
                Section(group.platform) {
                    ForEach(group.items) { item in
                        Button { onAdd(item) } label: {
                            HStack {
                                CatalogItemRow(item: item, showPlatform: false)
                                if item.entry(for: status) != nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.mutedText)
                                        .accessibilityLabel(status == .wishlist ? "Already on wishlist" : "Already in collection")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button {
                    onAddCustom()
                } label: {
                    Label(
                        results.isEmpty ? "No matches — Add \"\(searchText)\" as a Custom Entry" : "Can't find it? Add a Custom Entry",
                        systemImage: "plus.circle"
                    )
                }
                .disabled(!account.state.isSignedIn)
                .help(account.state.isSignedIn ? "" : "Sign in to add a custom catalog entry.")
            }
        }
    }
}

#Preview {
    AddToCollectionFlow(defaultStatus: .owned)
        .modelContainer(SampleData.previewContainer())
}
