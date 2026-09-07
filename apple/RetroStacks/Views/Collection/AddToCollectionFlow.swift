import SwiftUI
import SwiftData

/// Sheet: search the catalog, pick an entry, and create a `CollectionItem` for it.
struct AddToCollectionFlow: View {
    var defaultStatus: CollectionStatus

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\CatalogItem.name)]) private var catalog: [CatalogItem]
    @State private var searchText = ""
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
        NavigationStack {
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
                            Button {
                                add(item)
                            } label: {
                                HStack {
                                    CatalogItemRow(item: item, showPlatform: false)
                                    if alreadyExists(item) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search the catalog")
            .navigationTitle(defaultStatus == .wishlist ? "Add to Wishlist" : "Add to Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    private func alreadyExists(_ item: CatalogItem) -> Bool {
        item.entry(for: defaultStatus) != nil
    }

    private func add(_ item: CatalogItem) {
        CollectionActions.add(item, status: defaultStatus, in: modelContext)
        dismiss()
    }
}

#Preview {
    AddToCollectionFlow(defaultStatus: .owned)
        .modelContainer(SampleData.previewContainer())
}
