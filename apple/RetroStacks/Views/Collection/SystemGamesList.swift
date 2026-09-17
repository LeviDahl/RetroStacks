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

    /// This screen never had its own search field — it only ever showed
    /// whatever a *parent* screen's `.searchable()` happened to propagate
    /// down the nav stack, which isn't consistent across every way to reach
    /// this screen. Found live 2026-09-17: real per-platform search, always
    /// present regardless of entry point. `searchQuery` is `@State`, seeded
    /// from whatever the caller passed (so arriving here already filtered,
    /// e.g. from `CollectionSection`'s own search, still works) but from then
    /// on owned locally by this screen's own `.searchable()` field.
    @State private var searchQuery: String

    init(platform: Platform, mode: CollectionSection.Mode = .collection, searchText: String = "") {
        self.platform = platform
        self.mode = mode
        _searchQuery = State(initialValue: searchText)
        _scope = State(initialValue: mode == .wishlist ? .wanted : .owned)
        // Deliberately NOT seeded synchronously here anymore — found live
        // 2026-09-17 that `platform.catalogItems`'s first access (a SwiftData
        // relationship fault, thousands of rows post-IGDB) took 1-3+ seconds
        // against a real store, and running that inside `init` blocks the
        // main thread during the navigation push itself, freezing the whole
        // app for that long. `.task(id:)` below now does this asynchronously
        // instead, trading the old "no empty-state flash" guarantee for "the
        // screen navigates immediately and shows a spinner" — a real
        // regression on data volumes where the synchronous cost was small,
        // a real fix on today's, where it isn't.
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
    /// Whether the signed-in user can bulk-exclude items from the *shared*
    /// catalog (see `AdminCatalogCurationService`) — checked once per visit
    /// via a real RPC (the client can't read the `admins` table directly to
    /// know this locally), not cached across screens. `false` while the
    /// check is pending, same as signed-out: fails closed, never shows the
    /// admin action to someone who isn't one.
    @State private var isAdmin = false
    @State private var isExcluding = false
    @State private var isShowingExcludeConfirm = false
    @AppStorage("system.kindFilter") private var kindRaw = KindFilter.games.rawValue
    @AppStorage("system.sortField") private var sortRaw = SortField.title.rawValue
    /// Applies to whichever `sortField` is active — add a new field and it's
    /// reversible for free, no per-field "reverse" case needed.
    @AppStorage("system.sortAscending") private var sortAscending = true
    @AppStorage("system.showAbout") private var showAbout = true
    /// Off by default: hidden items (homebrew/ROM-hacks/etc. someone's
    /// explicitly not interested in — see `CatalogItem.isHidden`) stay out of
    /// normal browsing. Turning this on is how you get back to one to unhide
    /// it — there's no separate management screen for v1.
    @AppStorage("system.showHidden") private var showHidden = false

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

    /// Filter+sort over a whole platform's catalog (~1,900 items for SNES)
    /// used to run as a plain computed property on *every* body evaluation —
    /// since `liveEntries` below is an unscoped `@Query`, that fired on every
    /// add/remove/edit anywhere in the app, not just this screen. Fine at
    /// ~400 items/platform, noticeably slow found live 2026-09-17 at ~5x that
    /// post-IGDB. Cached here, refreshed only via `.task(id:)` in `body` on
    /// real dependency changes. `shown`'s filter over this stays a plain
    /// computed property (a cheap O(n) pass, not a re-sort). Accepted
    /// tradeoff: "Value" sort won't live-reorder as a price changes
    /// elsewhere — re-sorts on the next real dependency change instead of
    /// reintroducing an `liveEntries` watch for a narrow case.
    @State private var cachedCatalog: [CatalogItem] = []
    /// `false` until `recomputeCatalog()` has run at least once — distinguishes
    /// "still loading" from "genuinely nothing here" so the empty state
    /// doesn't flash a wrong, misleading message while `.task(id:)` is still
    /// working. See the `init` doc comment: this is a deliberate tradeoff for
    /// not blocking the main thread on navigation.
    @State private var hasLoadedCatalog = false

    private var catalogCacheKey: String {
        "\(platform.slug)|\(kindFilter.rawValue)|\(searchQuery)|\(sortField.rawValue)|\(sortAscending)|\(showHidden)"
    }

    private func recomputeCatalog() {
        cachedCatalog = Self.computeCatalog(
            platform: platform, kindFilter: kindFilter, searchText: searchQuery,
            sortField: sortField, sortAscending: sortAscending, showHidden: showHidden
        )
        hasLoadedCatalog = true
    }

    private static func computeCatalog(
        platform: Platform, kindFilter: KindFilter, searchText: String,
        sortField: SortField, sortAscending: Bool, showHidden: Bool
    ) -> [CatalogItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = platform.catalogItems.filter { item in
            (showHidden || !item.isHidden)
                && (kindFilter.kind == nil || item.kind == kindFilter.kind)
                && (q.isEmpty
                    || item.name.lowercased().contains(q)
                    || (item.variant?.lowercased().contains(q) ?? false)
                    || (item.manufacturerOrPublisher?.lowercased().contains(q) ?? false))
        }
        return filtered.sorted { a, b in
            switch sortField {
            case .title:
                return ascendingCompare(a.name.lowercased(), b.name.lowercased(), sortAscending: sortAscending)
            case .releaseYear:
                return ascendingCompare(a.releaseYearNA ?? .max, b.releaseYearNA ?? .max,
                                         sortAscending: sortAscending, tiebreak: (a.name, b.name))
            case .publisher:
                return ascendingCompare(a.manufacturerOrPublisher ?? "~", b.manufacturerOrPublisher ?? "~",
                                         sortAscending: sortAscending, tiebreak: (a.name, b.name))
            case .value:
                let av = a.ownedEntry?.estimatedValue ?? a.headlineValue ?? 0
                let bv = b.ownedEntry?.estimatedValue ?? b.headlineValue ?? 0
                return ascendingCompare(av, bv, sortAscending: sortAscending, tiebreak: (a.name, b.name))
            }
        }
    }

    /// One comparator every sort field routes through, `sortAscending`-aware.
    /// Equal primary values fall back to `tiebreak` (always name-ascending, so
    /// ties never look shuffled) when one is supplied. `static` (no `self`) so
    /// `computeCatalog` can call it from `init`, before `self` is fully formed.
    private static func ascendingCompare<T: Comparable>(
        _ lhs: T, _ rhs: T, sortAscending: Bool, tiebreak: (String, String)? = nil
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

    private var shown: [CatalogItem] { cachedCatalog.filter { matches($0, scope) } }

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
            .task(id: catalogCacheKey) { recomputeCatalog() }
            .task { isAdmin = await AdminCatalogCurationService().checkIsAdmin() }
            .searchable(text: $searchQuery, prompt: "Search \(platform.shortName)")
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
            .confirmationDialog(
                "Exclude \(picked.count) \(picked.count == 1 ? "item" : "items") from the shared catalog?",
                isPresented: $isShowingExcludeConfirm,
                titleVisibility: .visible
            ) {
                Button("Exclude for Everyone", role: .destructive) { commitBulkExclude() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes them from the catalog every user sees, not just this device. Reversible from the Supabase SQL Editor if it's a mistake.")
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
            modelContext.saveLoggingErrors(reportingAs: .localSave)
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

            if !hasLoadedCatalog {
                Section {
                    loadingState
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else if shown.isEmpty {
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

                if !hasLoadedCatalog {
                    loadingState
                } else if shown.isEmpty {
                    emptyState
                } else {
                    Text("\(shown.count) \(shown.count == 1 ? "title" : "titles")")
                        .font(.subheadline)
                        .foregroundStyle(.mutedText)

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
            .contextMenu {
                Button {
                    withAnimation { toggleHidden(catalogItem) }
                } label: {
                    Label(
                        catalogItem.isHidden ? "Unhide" : "Hide",
                        systemImage: catalogItem.isHidden ? "eye" : "eye.slash"
                    )
                }
            }
            .opacity(catalogItem.isHidden ? 0.5 : 1) // dimmed to read as "set aside," not normal
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
            Divider()
            Toggle(isOn: $showHidden) {
                Label("Show Hidden Items", systemImage: "eye.slash")
            }
        } label: {
            Label("\(kindFilter.label) · \(sortField.label) \(sortAscending ? "↑" : "↓")",
                  systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func toggleHidden(_ catalogItem: CatalogItem) {
        catalogItem.isHidden.toggle()
        modelContext.saveLoggingErrors(reportingAs: .localSave)
        recomputeCatalog()
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

    /// Shown while `.task(id:)` is still faulting/filtering/sorting the
    /// platform's catalog — see `hasLoadedCatalog`. Same region as
    /// `emptyState` below, for the same reason.
    private var loadingState: some View {
        ProgressView("Loading \(platform.shortName) catalog…")
            .frame(maxWidth: .infinity, minHeight: 240)
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
            .swipeActions(edge: .leading) {
                Button {
                    withAnimation { toggleHidden(catalogItem) }
                } label: {
                    Label(
                        catalogItem.isHidden ? "Unhide" : "Hide",
                        systemImage: catalogItem.isHidden ? "eye" : "eye.slash"
                    )
                }
                .tint(.mutedText)
            }
            .opacity(catalogItem.isHidden ? 0.5 : 1) // dimmed to read as "set aside," not normal
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
        let bySlug = Dictionary(cachedCatalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
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

    /// Server call first, local reflection only after it actually succeeds —
    /// same reasoning as `CustomCatalogItemActions.create`: no offline queue
    /// here, so local and remote must agree, not diverge. Sets `isHidden`
    /// locally rather than deleting the local `CatalogItem` outright: a
    /// hard delete would cascade-delete any `CollectionItem` someone already
    /// has for it (`CatalogItem`'s relationship is `deleteRule: .cascade`),
    /// silently destroying a real collection record as a side effect of an
    /// unrelated curation action. `isHidden` gets the same immediate visual
    /// result (out of normal browsing) with none of that risk.
    private func commitBulkExclude() {
        let slugs = Array(picked)
        isExcluding = true
        Task {
            do {
                try await AdminCatalogCurationService().exclude(slugs: slugs)
                let slugSet = Set(slugs)
                for item in cachedCatalog where slugSet.contains(item.slug) {
                    item.isHidden = true
                }
                modelContext.saveLoggingErrors(reportingAs: .localSave)
                withAnimation {
                    picked.removeAll()
                    selecting = false
                }
                recomputeCatalog()
                successToast = "Excluded \(slugs.count) from the catalog for everyone"
            } catch {
                successToast = "Couldn't exclude: \((error as? CatalogError)?.userMessage ?? error.localizedDescription)"
            }
            isExcluding = false
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
                if isAdmin {
                    Button(role: .destructive) {
                        isShowingExcludeConfirm = true
                    } label: {
                        Label("Exclude", systemImage: "eye.slash")
                    }
                    .disabled(picked.isEmpty || isExcluding)
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
