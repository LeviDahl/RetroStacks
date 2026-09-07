import SwiftUI
import SwiftData

/// Drill-down for one platform. Shows the platform's whole catalog, scoped by
/// ownership (Owned / Missing / All) so you can add what you don't have without
/// leaving the page. A kind filter (Games by default) narrows it further.
struct SystemGamesList: View {
    var platform: Platform
    var mode: CollectionSection.Mode
    var searchText: String = ""

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<CollectionItem> { $0.deletedAt == nil })
    private var liveEntries: [CollectionItem]

    @State private var scope: Scope = .all
    @AppStorage("system.kindFilter") private var kindRaw = KindFilter.games.rawValue
    @AppStorage("system.sortField") private var sortRaw = SortField.title.rawValue

    enum SortField: String, CaseIterable, Identifiable {
        case title, releaseYear, publisher, value
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title: "Title"
            case .releaseYear: "Release Year"
            case .publisher: "Publisher"
            case .value: "Value"
            }
        }
    }
    private var sortField: SortField { SortField(rawValue: sortRaw) ?? .title }

    enum Scope: String, CaseIterable, Identifiable {
        case inList, missing, all
        var id: String { rawValue }
        func label(_ mode: CollectionSection.Mode) -> String {
            switch self {
            case .inList:  mode == .wishlist ? "Wanted" : "Owned"
            case .missing: mode == .wishlist ? "Not Wanted" : "Missing"
            case .all:     "All"
            }
        }
    }

    enum KindFilter: String, CaseIterable, Identifiable {
        case games, consoles, accessories, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .games: "Games"
            case .consoles: "Consoles"
            case .accessories: "Accessories"
            case .all: "Everything"
            }
        }
        var kind: ItemKind? {
            switch self {
            case .games: .game
            case .consoles: .console
            case .accessories: .accessory
            case .all: nil
            }
        }
    }

    private var kindFilter: KindFilter { KindFilter(rawValue: kindRaw) ?? .games }

    // MARK: Derived

    private var catalog: [CatalogItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = platform.catalogItems.filter { item in
            (kindFilter.kind == nil || item.kind == kindFilter.kind)
                && (q.isEmpty
                    || item.name.lowercased().contains(q)
                    || (item.variant?.lowercased().contains(q) ?? false)
                    || (item.manufacturerOrPublisher?.lowercased().contains(q) ?? false))
        }
        return filtered.sorted { a, b in
            switch sortField {
            case .title:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .releaseYear:
                return (a.releaseYearNA ?? .max, a.name.lowercased())
                    < (b.releaseYearNA ?? .max, b.name.lowercased())
            case .publisher:
                return (a.manufacturerOrPublisher ?? "~", a.name.lowercased())
                    < (b.manufacturerOrPublisher ?? "~", b.name.lowercased())
            case .value:
                let av = a.entry(for: mode.status)?.estimatedValue ?? a.headlineValue ?? 0
                let bv = b.entry(for: mode.status)?.estimatedValue ?? b.headlineValue ?? 0
                return av == bv
                    ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    : av > bv
            }
        }
    }

    private func inList(_ c: CatalogItem) -> Bool { c.entry(for: mode.status) != nil }

    private var shown: [CatalogItem] {
        switch scope {
        case .inList:  catalog.filter(inList)
        case .missing: catalog.filter { !inList($0) }
        case .all:     catalog
        }
    }

    private var counts: (inList: Int, missing: Int, all: Int) {
        let all = catalog.count
        let owned = catalog.filter(inList).count
        return (owned, all - owned, all)
    }

    private var summary: CollectionStats.SystemSummary? {
        CollectionStatsBuilder.systemSummaries(from: liveEntries, status: mode.status)
            .first { $0.platformSlug == platform.slug }
    }

    // MARK: Body

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Picker("Scope", selection: $scope) {
                        Text("\(Scope.inList.label(mode)) · \(counts.inList)").tag(Scope.inList)
                        Text("\(Scope.missing.label(mode)) · \(counts.missing)").tag(Scope.missing)
                        Text("All · \(counts.all)").tag(Scope.all)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Menu {
                        Picker("Show", selection: $kindRaw) {
                            ForEach(KindFilter.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Picker("Sort by", selection: $sortRaw) {
                            ForEach(SortField.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("\(kindFilter.label) · \(sortField.label)",
                              systemImage: "line.3.horizontal.decrease.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)

                if mode == .collection, let summary {
                    SystemSummaryStrip(summary: summary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(shown) { catalogItem in
                    PlatformCatalogRow(
                        catalogItem: catalogItem,
                        listStatus: mode.status,
                        onAdd: {
                            withAnimation {
                                _ = CollectionActions.add(catalogItem, status: mode.status, in: modelContext)
                            }
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        if let owned = catalogItem.entry(for: mode.status) {
                            Button(role: .destructive) {
                                withAnimation { CollectionActions.remove(owned, in: modelContext) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("\(shown.count) \(shown.count == 1 ? "title" : "titles")")
            }
        }
        .navigationTitle(platform.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: scope == .missing ? "checkmark.circle" : mode.status.symbol)
                } description: {
                    Text(emptyMessage)
                }
            }
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .missing: "Nothing missing"
        case .inList: mode == .wishlist ? "Nothing wanted here" : "Nothing owned here"
        case .all: "No \(kindFilter.label.lowercased()) catalogued"
        }
    }

    private var emptyMessage: String {
        switch scope {
        case .missing:
            "You have every \(kindFilter.label.lowercased().dropLast()) catalogued for \(platform.shortName)."
        case .inList:
            "Switch to Missing to add \(kindFilter.label.lowercased()) from \(platform.shortName)."
        case .all:
            "The catalog has no \(kindFilter.label.lowercased()) for \(platform.shortName) yet."
        }
    }
}

// MARK: - Row

/// A catalog row inside a platform drill-down: title + meta on the left,
/// ownership state or a one-tap Add on the right.
struct PlatformCatalogRow: View {
    var catalogItem: CatalogItem
    var listStatus: CollectionStatus
    var onAdd: () -> Void

    private var entry: CollectionItem? { catalogItem.entry(for: listStatus) }

    var body: some View {
        HStack(spacing: 12) {
            if let entry {
                NavigationLink(value: entry) { rowBody }.buttonStyle(.plain)
            } else {
                NavigationLink(value: catalogItem) { rowBody }.buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.vertical, 3)
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            ItemThumbnail(
                kind: catalogItem.kind,
                platformSymbol: catalogItem.platform?.iconSystemName,
                imageName: catalogItem.imageName,
                imageURL: catalogItem.imageURL,
                size: 48, cornerRadius: 10
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(catalogItem.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(catalogItem.kind.displayName)
                    if let year = catalogItem.releaseYearNA { Text("·"); Text(String(year)) }
                    if let pub = catalogItem.manufacturerOrPublisher { Text("·"); Text(pub).lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let entry {
            VStack(alignment: .trailing, spacing: 3) {
                if let value = entry.estimatedValue {
                    Text(Money.string(value)).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    CompletenessBadge(completeness: entry.completeness)
                    Image(systemName: listStatus == .wishlist ? "star.fill" : "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(listStatus == .wishlist ? .yellow : .green)
                }
            }
        } else {
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            .help(listStatus == .wishlist ? "Add to wishlist" : "Add to collection")
        }
    }
}

// MARK: - Summary strip

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
            if summary.remainingValue > 0 {
                Divider().frame(height: 34)
                metric("To finish", Money.string(summary.remainingValue))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let platform = try! container.mainContext.fetch(FetchDescriptor<Platform>())
        .first { $0.slug == "snes" }!
    NavigationStack {
        SystemGamesList(platform: platform, mode: .collection)
            .navigationDestination(for: CollectionItem.self) { CollectionItemDetailView(item: $0) }
            .navigationDestination(for: CatalogItem.self) { CatalogItemDetailView(item: $0) }
    }
    .modelContainer(container)
}
