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
    @State private var quickAddTarget: CatalogItem?
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var bulkCompleteness: Completeness = .loose
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
        ScrollViewReader { proxy in
            listBody
                #if os(iOS)
                .overlay(alignment: .trailing) {
                    if showScrubber {
                        AZScrubber(letters: letterIndex.map(\.letter)) { letter in
                            if let slug = letterIndex.first(where: { $0.letter == letter })?.slug {
                                proxy.scrollTo(slug, anchor: .top)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                }
                #endif
        }
    }

    private var listBody: some View {
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
                    rowContent(for: catalogItem)
                        .id(catalogItem.slug)
                }
            } header: {
                Text("\(shown.count) \(shown.count == 1 ? "title" : "titles")")
            }
        }
        .navigationTitle(platform.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if canBulkAdd {
                ToolbarItem {
                    Button(selecting ? "Done" : "Select") {
                        withAnimation {
                            selecting.toggle()
                            if !selecting { picked.removeAll() }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { bulkAddBar }
        }
        .onChange(of: scope) { _, _ in if selecting { picked.removeAll() } }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: scope == .missing ? "checkmark.circle" : mode.status.symbol)
                } description: {
                    Text(emptyMessage)
                }
            }
        }
        .sheet(item: $quickAddTarget) { item in
            QuickAddSheet(catalogItem: item) { completeness, condition in
                withAnimation {
                    _ = CollectionActions.add(
                        item,
                        status: .owned,
                        completeness: completeness,
                        condition: condition,
                        in: modelContext
                    )
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

    // MARK: Rows

    @ViewBuilder
    private func rowContent(for catalogItem: CatalogItem) -> some View {
        if selecting {
            SelectableCatalogRow(
                catalogItem: catalogItem,
                alreadyIn: inList(catalogItem),
                picked: picked.contains(catalogItem.slug),
                toggle: { togglePick(catalogItem) }
            )
        } else {
            PlatformCatalogRow(
                catalogItem: catalogItem,
                listStatus: mode.status,
                onAdd: {
                    // Owned copies get the quick-add modal (completeness +
                    // condition); a wishlist add has nothing to configure.
                    if mode.status == .owned {
                        quickAddTarget = catalogItem
                    } else {
                        withAnimation {
                            _ = CollectionActions.add(catalogItem, status: mode.status, in: modelContext)
                        }
                    }
                },
                onToggleWishlist: mode.status == .owned ? { toggleWishlist(catalogItem) } : nil
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
    }

    // MARK: A–Z jump index

    /// First row (by slug) for each leading letter of the shown titles, in order.
    private var letterIndex: [(letter: String, slug: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for item in shown {
            let letter = Self.indexLetter(for: item.displayTitle)
            if seen.insert(letter).inserted { out.append((letter, item.slug)) }
        }
        return out.map { (letter: $0.0, slug: $0.1) }
    }

    private var showScrubber: Bool {
        sortField == .title && !selecting && letterIndex.count > 3 && shown.count > 40
    }

    static func indexLetter(for title: String) -> String {
        guard let first = title.uppercased().unicodeScalars.first else { return "#" }
        return CharacterSet.uppercaseLetters.contains(first) ? String(first) : "#"
    }

    // MARK: Bulk add

    /// Only worth offering when the current view has rows you don't already have.
    private var canBulkAdd: Bool {
        scope != .inList && shown.contains { !inList($0) }
    }

    private func togglePick(_ item: CatalogItem) {
        guard !inList(item) else { return }
        if picked.contains(item.slug) { picked.remove(item.slug) } else { picked.insert(item.slug) }
    }

    private func toggleWishlist(_ item: CatalogItem) {
        withAnimation {
            if let existing = item.entry(for: .wishlist) {
                CollectionActions.remove(existing, in: modelContext)
            } else {
                _ = CollectionActions.add(item, status: .wishlist, in: modelContext)
            }
        }
    }

    private func commitBulkAdd() {
        let bySlug = Dictionary(catalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let condition: ConditionGrade? = mode.status == .owned ? .good : nil
        let completeness: Completeness? = mode.status == .owned ? bulkCompleteness : nil
        withAnimation {
            for slug in picked {
                guard let item = bySlug[slug] else { continue }
                _ = CollectionActions.add(
                    item, status: mode.status,
                    completeness: completeness, condition: condition,
                    in: modelContext
                )
            }
            picked.removeAll()
            selecting = false
        }
    }

    @ViewBuilder
    private var bulkAddBar: some View {
        VStack(spacing: 8) {
            if mode.status == .owned {
                Picker("Completeness", selection: $bulkCompleteness) {
                    Text("Loose").tag(Completeness.loose)
                    Text("Boxed").tag(Completeness.boxedNoManual)
                    Text("CIB").tag(Completeness.completeInBox)
                    Text("Sealed").tag(Completeness.sealed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Button("Cancel") {
                    withAnimation { picked.removeAll(); selecting = false }
                }
                Spacer()
                Button {
                    commitBulkAdd()
                } label: {
                    Text(picked.isEmpty
                         ? "Select items to add"
                         : "Add \(picked.count) to \(mode == .wishlist ? "wishlist" : "collection")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty)
            }
        }
        .padding(12)
        .background(.bar)
    }
}

// MARK: - Row

/// Thumbnail + title + meta line — the shared visual for every catalog row in
/// the drill-down (plain, selectable, hover).
struct CatalogRowContent: View {
    var catalogItem: CatalogItem

    var body: some View {
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
}

/// A catalog row inside a platform drill-down: title + meta on the left,
/// ownership state or a one-tap Add on the right. On macOS a wishlist toggle
/// appears on hover.
struct PlatformCatalogRow: View {
    var catalogItem: CatalogItem
    var listStatus: CollectionStatus
    var onAdd: () -> Void
    var onToggleWishlist: (() -> Void)? = nil

    @State private var hovering = false

    private var entry: CollectionItem? { catalogItem.entry(for: listStatus) }
    private var wishlisted: Bool { catalogItem.entry(for: .wishlist) != nil }

    var body: some View {
        HStack(spacing: 12) {
            if let entry {
                NavigationLink(value: entry) { CatalogRowContent(catalogItem: catalogItem) }
                    .buttonStyle(.plain)
            } else {
                NavigationLink(value: catalogItem) { CatalogRowContent(catalogItem: catalogItem) }
                    .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if let onToggleWishlist, hovering || wishlisted {
                Button(action: onToggleWishlist) {
                    Image(systemName: wishlisted ? "star.fill" : "star")
                        .foregroundStyle(wishlisted ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(wishlisted ? "Remove from wishlist" : "Add to wishlist")
                .transition(.opacity)
            }

            trailing
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        #endif
        .swipeActions(edge: .leading) {
            if let onToggleWishlist {
                Button(action: onToggleWishlist) {
                    Label(wishlisted ? "Unwish" : "Wishlist",
                          systemImage: wishlisted ? "star.slash" : "star")
                }
                .tint(.yellow)
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

/// Row shown while the list is in multi-select ("Select") mode: a checkbox in
/// place of the disclosure / add button. Rows already in the list are locked.
struct SelectableCatalogRow: View {
    var catalogItem: CatalogItem
    var alreadyIn: Bool
    var picked: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: alreadyIn ? "checkmark.circle.fill"
                      : picked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(alreadyIn ? .green : picked ? Color.accentColor : .secondary)
                CatalogRowContent(catalogItem: catalogItem)
                Spacer(minLength: 8)
                if alreadyIn {
                    Text("In list").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyIn)
    }
}

// MARK: - A–Z scrubber

/// Trailing-edge letter index for long, title-sorted catalogs. Tap or drag a
/// letter to jump. iOS only — macOS has a real scrollbar and more room.
struct AZScrubber: View {
    var letters: [String]
    var onSelect: (String) -> Void

    @State private var active: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active == letter ? Color.white : Color.accentColor)
                    .frame(width: 16, height: 15)
                    .background {
                        if active == letter {
                            Circle().fill(Color.accentColor)
                        }
                    }
            }
        }
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let count = letters.count
                    guard count > 0 else { return }
                    let rowH: CGFloat = 16
                    let idx = min(max(Int(value.location.y / rowH), 0), count - 1)
                    let letter = letters[idx]
                    if letter != active {
                        active = letter
                        onSelect(letter)
                    }
                }
                .onEnded { _ in active = nil }
        )
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel("Section index")
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
