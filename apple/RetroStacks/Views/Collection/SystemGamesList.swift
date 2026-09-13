import SwiftUI
import SwiftData

/// The one screen for a single platform. A collapsible "about" header (the
/// mini-wiki) sits on top of the platform's whole catalog, scoped **Owned /
/// Wanted / Missing / All** so you can manage the collection and the wishlist
/// without leaving the page. A kind filter (Games by default) narrows it further.
///
/// macOS gets its own layout: a poster-tile grid instead of a single-column
/// list, so a roomy window doesn't read as a stretched iPhone screen.
struct SystemGamesList: View {
    var platform: Platform
    /// Only sets the initial scope (My Collection → Owned, Wishlist → Wanted).
    var mode: CollectionSection.Mode
    var searchText: String

    init(platform: Platform, mode: CollectionSection.Mode = .collection, searchText: String = "") {
        self.platform = platform
        self.mode = mode
        self.searchText = searchText
        _scope = State(initialValue: mode == .wishlist ? .wanted : .owned)
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<CollectionItem> { $0.deletedAt == nil })
    private var liveEntries: [CollectionItem]

    @State private var scope: Scope
    @State private var quickAddTarget: CatalogItem?
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var bulkCompleteness: Completeness = .loose
    @State private var successToast: String?
    @State private var toastUndo: (() -> Void)?
    @AppStorage("system.kindFilter") private var kindRaw = KindFilter.games.rawValue
    @AppStorage("system.sortField") private var sortRaw = SortField.title.rawValue
    /// Applies to whichever `sortField` is active — add a new field and it's
    /// reversible for free, no per-field "reverse" case needed.
    @AppStorage("system.sortAscending") private var sortAscending = true
    @AppStorage("system.showAbout") private var showAbout = true

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
        case owned, wanted, missing, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .owned: "Owned"
            case .wanted: "Wanted"
            case .missing: "Missing"
            case .all: "All"
            }
        }
        /// Where a one-tap add from this scope lands.
        var addStatus: CollectionStatus { self == .wanted ? .wishlist : .owned }
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
                return ascendingCompare(a.name.lowercased(), b.name.lowercased())
            case .releaseYear:
                return ascendingCompare(a.releaseYearNA ?? .max, b.releaseYearNA ?? .max,
                                         tiebreak: (a.name, b.name))
            case .publisher:
                return ascendingCompare(a.manufacturerOrPublisher ?? "~", b.manufacturerOrPublisher ?? "~",
                                         tiebreak: (a.name, b.name))
            case .value:
                let av = a.ownedEntry?.estimatedValue ?? a.headlineValue ?? 0
                let bv = b.ownedEntry?.estimatedValue ?? b.headlineValue ?? 0
                return ascendingCompare(av, bv, tiebreak: (a.name, b.name))
            }
        }
    }

    /// One comparator every sort field routes through, `sortAscending`-aware.
    /// Equal primary values fall back to `tiebreak` (always name-ascending, so
    /// ties never look shuffled) when one is supplied.
    private func ascendingCompare<T: Comparable>(
        _ lhs: T, _ rhs: T, tiebreak: (String, String)? = nil
    ) -> Bool {
        if lhs != rhs { return sortAscending ? lhs < rhs : lhs > rhs }
        guard let tiebreak else { return false }
        return tiebreak.0.localizedCaseInsensitiveCompare(tiebreak.1) == .orderedAscending
    }

    private func matches(_ c: CatalogItem, _ scope: Scope) -> Bool {
        switch scope {
        case .owned:   c.entry(for: .owned) != nil
        case .wanted:  c.entry(for: .wishlist) != nil
        case .missing: c.entry(for: .owned) == nil
        case .all:     true
        }
    }

    /// True when the item is already in whatever list the current scope adds to.
    private func inList(_ c: CatalogItem) -> Bool { c.entry(for: scope.addStatus) != nil }

    private var shown: [CatalogItem] { catalog.filter { matches($0, scope) } }

    private var summary: CollectionStats.SystemSummary? {
        CollectionStatsBuilder.systemSummaries(from: liveEntries, status: .owned)
            .first { $0.platformSlug == platform.slug }
    }

    // MARK: Body

    var body: some View {
        content
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
            .toast(successToast, actionTitle: toastUndo != nil ? "Undo" : nil, action: toastUndo) {
                successToast = nil
                toastUndo = nil
            }
    }

    /// Swipe-to-remove has no confirmation (unlike the detail view's
    /// destructive menu action for the same change) — an "Undo" toast gives
    /// the same safety net without adding a blocking tap to the fast path.
    private func removeWithUndo(_ entry: CollectionItem, title: String) {
        CollectionActions.remove(entry, in: modelContext)
        successToast = "Removed \(title)"
        toastUndo = { [weak entry] in
            guard let entry else { return }
            entry.deletedAt = nil
            entry.touch()
            try? modelContext.save()
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macGrid
        #else
        ScrollViewReader { proxy in
            iosList
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
        }
        #endif
    }

    // MARK: iOS — List

    #if os(iOS)
    private var iosList: some View {
        List {
            Section {
                DisclosureGroup(isExpanded: $showAbout) {
                    AboutSystemCard(platform: platform, summary: summary)
                        .padding(.top, 6)
                } label: {
                    Text("About \(platform.shortName)").font(.subheadline.weight(.medium))
                }
            }

            Section {
                controlsRow
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)

                if let summary {
                    SystemSummaryStrip(summary: summary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }

            if shown.isEmpty {
                Section {
                    emptyState
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(shown) { catalogItem in
                        rowContent(for: catalogItem)
                            .id(catalogItem.slug)
                    }
                } header: {
                    Text("\(shown.count) \(shown.count == 1 ? "title" : "titles")")
                }
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            scopePicker
            filterSortMenu
        }
    }
    #endif

    // MARK: macOS — poster-tile grid

    #if os(macOS)
    private var macGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                aboutCard
                controlsBar

                if let summary {
                    SystemSummaryStrip(summary: summary)
                }

                if shown.isEmpty {
                    emptyState
                } else {
                    Text("\(shown.count) \(shown.count == 1 ? "title" : "titles")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: LayoutMetrics.cardColumns(), spacing: LayoutMetrics.cardSpacing) {
                        ForEach(shown) { catalogItem in
                            tile(for: catalogItem)
                        }
                    }
                }
            }
            .padding(LayoutMetrics.screenEdgePadding)
        }
    }

    private var aboutCard: some View {
        DisclosureGroup(isExpanded: $showAbout) {
            AboutSystemCard(platform: platform, summary: summary)
                .padding(.top, 10)
        } label: {
            Text("About \(platform.shortName)").font(.headline)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous))
    }

    /// A floating control cluster over content — the appropriate place for
    /// Liquid Glass (chrome, not content). Hugs its own content and anchors
    /// left; it must NOT stretch to the row's full proposed width, or the
    /// segmented control stretches with it and the glass pill reads as an
    /// oversized, mostly-empty bar with the filter icon stranded far right.
    private var controlsBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                scopePicker
                filterSortMenu
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func tile(for catalogItem: CatalogItem) -> some View {
        if selecting {
            SelectableCatalogTile(
                catalogItem: catalogItem,
                alreadyIn: inList(catalogItem),
                picked: picked.contains(catalogItem.slug),
                toggle: { togglePick(catalogItem) }
            )
        } else {
            let addStatus = scope.addStatus
            SystemCatalogTile(
                catalogItem: catalogItem,
                listStatus: addStatus,
                onAdd: { handleAdd(catalogItem, status: addStatus) },
                onToggleWishlist: addStatus == .owned ? { toggleWishlist(catalogItem) } : nil,
                onRemove: catalogItem.entry(for: addStatus).map { entry in { withAnimation { CollectionActions.remove(entry, in: modelContext) } }
                }
            )
        }
    }
    #endif

    // MARK: Shared controls

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            ForEach(Scope.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var filterSortMenu: some View {
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
            Divider()
            Toggle(isOn: $sortAscending) {
                Label("Ascending", systemImage: "arrow.up")
            }
        } label: {
            Label("\(kindFilter.label) · \(sortField.label) \(sortAscending ? "↑" : "↓")",
                  systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func handleAdd(_ catalogItem: CatalogItem, status: CollectionStatus) {
        // Owned copies get the quick-add modal (completeness + condition); a
        // wishlist add has nothing to configure.
        if status == .owned {
            quickAddTarget = catalogItem
        } else {
            withAnimation {
                _ = CollectionActions.add(catalogItem, status: status, in: modelContext)
            }
        }
    }

    private var emptySymbol: String {
        switch scope {
        case .owned: "tray"
        case .wanted: "star"
        case .missing: "checkmark.circle"
        case .all: "square.grid.2x2"
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .owned: "Nothing owned here"
        case .wanted: "Nothing on the wishlist"
        case .missing: "Nothing missing"
        case .all: "No \(kindFilter.label.lowercased()) catalogued"
        }
    }

    /// Scoped to just the list/grid region (below the About card, controls,
    /// and summary strip) rather than the whole screen — a screen-wide
    /// `.overlay` here centers across all that header content too and ends up
    /// clipped against the stats strip right above it.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyMessage)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var emptyMessage: String {
        let kind = kindFilter.label.lowercased()
        switch scope {
        case .owned:
            return "Switch to Missing to add \(kind) from \(platform.shortName)."
        case .wanted:
            return "Star \(kind) from Missing or All to track them here."
        case .missing:
            return "You have every \(kind.dropLast()) catalogued for \(platform.shortName)."
        case .all:
            return "The catalog has no \(kind) for \(platform.shortName) yet."
        }
    }

    // MARK: iOS rows

    #if os(iOS)
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
            let addStatus = scope.addStatus
            PlatformCatalogRow(
                catalogItem: catalogItem,
                listStatus: addStatus,
                onAdd: { handleAdd(catalogItem, status: addStatus) },
                onToggleWishlist: addStatus == .owned ? { toggleWishlist(catalogItem) } : nil
            )
            .swipeActions(edge: .trailing) {
                if let entry = catalogItem.entry(for: addStatus) {
                    Button(role: .destructive) {
                        withAnimation { removeWithUndo(entry, title: catalogItem.displayTitle) }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
    }
    #endif

    // MARK: A–Z jump index (iOS)

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
        sortField == .title && sortAscending && !selecting && letterIndex.count > 3 && shown.count > 40
    }

    static func indexLetter(for title: String) -> String {
        guard let first = title.uppercased().unicodeScalars.first else { return "#" }
        return CharacterSet.uppercaseLetters.contains(first) ? String(first) : "#"
    }

    // MARK: Bulk add

    /// Only worth offering when the current view has rows you don't already have.
    private var canBulkAdd: Bool {
        (scope == .missing || scope == .all) && shown.contains { !inList($0) }
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

    /// Bulk add from Missing/All targets the collection (owned); from Wanted it
    /// would be redundant. `.all` may include already-owned rows — those are
    /// locked in the picker, so this only ever adds new ones.
    private var bulkStatus: CollectionStatus { .owned }

    private func commitBulkAdd() {
        let bySlug = Dictionary(catalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        withAnimation {
            for slug in picked {
                guard let item = bySlug[slug] else { continue }
                _ = CollectionActions.add(
                    item, status: bulkStatus,
                    completeness: bulkCompleteness, condition: .good,
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
            Picker("Completeness", selection: $bulkCompleteness) {
                Text("Loose").tag(Completeness.loose)
                Text("Boxed").tag(Completeness.boxedNoManual)
                Text("CIB").tag(Completeness.completeInBox)
                Text("Sealed").tag(Completeness.sealed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button("Cancel") {
                    withAnimation { picked.removeAll(); selecting = false }
                }
                Spacer()
                Button {
                    commitBulkAdd()
                } label: {
                    Text(picked.isEmpty ? "Select items to add" : "Add \(picked.count) to collection")
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

// MARK: - iOS row

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
            .accessibilityHidden(true) // decorative — the title text beside it says the same thing
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
    var onToggleWishlist: (() -> Void)?

    @State private var hovering = false

    private var entry: CollectionItem? { catalogItem.entry(for: listStatus) }
    private var wishlisted: Bool { catalogItem.entry(for: .wishlist) != nil }

    /// On iOS there's no hover state, so gating on `hovering` (macOS-only)
    /// left the *only* way to add a not-yet-wishlisted item to the wishlist
    /// from this row an undiscoverable leading swipe — the button only ever
    /// appeared once an item was already wishlisted. Persistent on iOS;
    /// still hover-revealed on macOS, where it's genuinely just decluttering
    /// a denser layout, not hiding the only way in.
    private var wishlistButtonVisible: Bool {
        #if os(iOS)
        true
        #else
        hovering || wishlisted
        #endif
    }

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

            if let onToggleWishlist, wishlistButtonVisible {
                Button(action: onToggleWishlist) {
                    Image(systemName: wishlisted ? "star.fill" : "star")
                        .foregroundStyle(wishlisted ? .accentGold : .secondary)
                }
                .buttonStyle(.borderless)
                .help(wishlisted ? "Remove from wishlist" : "Add to wishlist")
                .accessibilityLabel(wishlisted ? "Remove from wishlist" : "Add to wishlist")
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
                // Fixed, not `.accentGold` — this is a fill with the
                // system's own white label drawn on top, not text-on-wash,
                // so it needs to stay dark enough for white-on-top contrast
                // in *both* appearances, not flip like `.accentGold` does.
                .tint(Color(red: 0.471, green: 0.337, blue: 0.0))
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
                        .foregroundStyle(listStatus == .wishlist ? .accentGold : .accentGreen)
                        .accessibilityLabel(listStatus == .wishlist ? "Wishlisted" : "Owned")
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            .help(listStatus == .wishlist ? "Add to wishlist" : "Add to collection")
            .accessibilityLabel(listStatus == .wishlist ? "Add to wishlist" : "Add to collection")
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
                    .foregroundStyle(alreadyIn ? .accentGreen : picked ? Color.accentColor : .secondary)
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
        .glassEffect(.regular, in: Capsule())
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
    // #Preview only, fixture data is always valid.
    // swiftlint:disable:next force_try
    let platform = try! container.mainContext.fetch(FetchDescriptor<Platform>())
        // "snes" is always seeded.
        // swiftlint:disable:next force_unwrapping
        .first { $0.slug == "snes" }!
    NavigationStack {
        SystemGamesList(platform: platform, mode: .collection)
            .navigationDestination(for: CollectionItem.self) { CollectionItemDetailView(item: $0) }
            .navigationDestination(for: CatalogItem.self) { CatalogItemDetailView(item: $0) }
    }
    .modelContainer(container)
}
