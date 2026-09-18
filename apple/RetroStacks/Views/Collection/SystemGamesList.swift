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
    /// Narrows to items matching *both* of the two real, IGDB-verified
    /// signals for likely bootlegs/ROM hacks/homebrew that slipped into the
    /// IGDB import as if they were real releases (found live 2026-09-17,
    /// checked against real `curl` results, not guessed — see
    /// `BACKLOG.md`'s Phase 5 section for the full account):
    /// `manufacturerOrPublisher` missing or credited on very few other items
    /// on this platform (a real publisher published many games; a ROM
    /// hacker's own handle, which IGDB's community data structurally can't
    /// tell apart from a real publisher credit, published exactly one), AND
    /// `releaseYearNA` missing or past the platform's own
    /// `discontinuedYearNA` (a real release falls inside the platform's
    /// actual commercial window; every hack checked was either dated years
    /// to decades later or not dated at all). Requiring *both* — not
    /// either — is deliberate: a real but obscure publisher with a correct
    /// period date won't match, and neither will a hack that happens to
    /// credit a real company by mistake.
    @AppStorage("system.reviewCandidatesOnly") private var reviewCandidatesOnly = false

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
        "\(platform.slug)|\(kindFilter.rawValue)|\(searchQuery)|\(sortField.rawValue)|\(sortAscending)|\(showHidden)|\(reviewCandidatesOnly)"
    }

    private func recomputeCatalog() {
        cachedCatalog = Self.computeCatalog(
            platform: platform, kindFilter: kindFilter, searchText: searchQuery,
            sortField: sortField, sortAscending: sortAscending, showHidden: showHidden,
            reviewCandidatesOnly: reviewCandidatesOnly
        )
        hasLoadedCatalog = true
    }

    // `rarePublisherThreshold`, `isReviewCandidate`, `computeCatalog`, and
    // `ascendingCompare` moved to `SystemGamesListCatalog.swift` (file_length)
    // — pure logic with no dependency on `self`, same reasoning as the
    // `SystemGamesListRows.swift` split.

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
                if canSelect {
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
            Divider()
            Toggle(isOn: $reviewCandidatesOnly) {
                Label("Review Candidates Only", systemImage: "questionmark.circle")
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

    // `indexLetter` moved to `SystemGamesListCatalog.swift` alongside the
    // other pure static helpers.

    // MARK: Bulk actions

    /// Available in every scope now, not just Missing/All — bulk-select is
    /// also how you bulk-*remove* (Owned/Wanted) or bulk-exclude (any
    /// scope), not only bulk-add, so gating it to "has something addable"
    /// stopped making sense once those other actions existed. `> 1` (not
    /// `> 0`): bulk-anything is meaningless with just one row to act on.
    private var canSelect: Bool { shown.count > 1 }

    /// No "already in your collection" lock (removed 2026-09-18) — that only
    /// ever made sense while Select meant bulk-*add* (can't add what you
    /// already have). Now it also backs bulk-remove (Owned/Wanted scope,
    /// where *every* shown row is already in the list by definition — the
    /// old lock would have made every row unpickable there) and bulk-exclude
    /// (whether you personally own an item has nothing to do with whether it
    /// belongs in the shared catalog). Each commit action skips whatever
    /// doesn't apply to a given picked item instead.
    private func togglePick(_ item: CatalogItem) {
        if picked.contains(item.slug) { picked.remove(item.slug) } else { picked.insert(item.slug) }
    }

    private var isAllShownSelected: Bool { !shown.isEmpty && picked.count == shown.count }

    private func toggleSelectAll() {
        picked = isAllShownSelected ? [] : Set(shown.map(\.slug))
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

    /// Bulk add always targets owned, regardless of scope — upgrading a
    /// Wanted item to owned is a reasonable bulk action too, not just
    /// Missing/All. Picking an already-owned row is harmless now: `Collection
    /// Actions.add` no-ops on an existing entry for that status rather than
    /// duplicating it.
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

    /// The bulk-add undo path, and the reason `togglePick` no longer locks
    /// already-in rows: removes whatever entry matches the *current scope's*
    /// status (Owned/All → owned, Wanted → wishlist) for each picked item
    /// that actually has one, silently skipping picked items that don't —
    /// same "just skip what doesn't apply" shape as `CollectionActions.add`'s
    /// own no-op-if-existing guard, just for the opposite direction.
    private func commitBulkRemove() {
        let bySlug = Dictionary(cachedCatalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        withAnimation {
            for slug in picked {
                guard let item = bySlug[slug], let entry = item.entry(for: scope.addStatus) else { continue }
                CollectionActions.remove(entry, in: modelContext)
            }
            picked.removeAll()
            selecting = false
        }
    }

    /// Server call first, local reflection only after it actually succeeds —
    /// same reasoning as `CustomCatalogItemActions.create`: no offline queue
    /// here, so local and remote must agree, not diverge. Same safe-delete-
    /// or-hide split `CatalogSyncService.reconcile`'s pruning pass uses:
    /// deletes the local `CatalogItem` outright when nobody's collection
    /// *currently* references it, so every count reading through
    /// `Platform.visibleCatalogItems` is correct immediately, not just
    /// after the next sync's own pruning pass catches up. Falls back to
    /// `isHidden = true` only when someone owns or wishlists it — a hard
    /// delete there would cascade-delete their real `CollectionItem`
    /// (`deleteRule: .cascade`) as a side effect of an unrelated curation
    /// action. Checks `liveEntries`, not raw `collectionEntries` — a
    /// tombstoned (soft-removed) entry from a since-undone add still counts
    /// as "owned" under the raw relationship, which is exactly what
    /// happened here once already (found live 2026-09-18).
    private func commitBulkExclude() {
        let slugs = Array(picked)
        isExcluding = true
        Task {
            do {
                try await AdminCatalogCurationService().exclude(slugs: slugs)
                let slugSet = Set(slugs)
                for item in cachedCatalog where slugSet.contains(item.slug) {
                    if item.liveEntries.isEmpty {
                        modelContext.delete(item)
                    } else {
                        item.isHidden = true
                    }
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

    /// Add only makes sense from Missing/All (Owned/Wanted rows are already
    /// there); Remove only makes sense from Owned/Wanted (Missing rows have
    /// nothing to remove) — mutually exclusive by scope, so the bar only
    /// ever shows one primary action, never both at once.
    private var canBulkAdd: Bool { scope == .missing || scope == .all }
    private var canBulkRemove: Bool { scope == .owned || scope == .wanted }

    @ViewBuilder
    private var bulkAddBar: some View {
        VStack(spacing: 8) {
            if canBulkAdd {
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
                Button(isAllShownSelected ? "Deselect All" : "Select All \(shown.count)") {
                    withAnimation { toggleSelectAll() }
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
                if canBulkRemove {
                    Button(role: .destructive) {
                        commitBulkRemove()
                    } label: {
                        Text(picked.isEmpty ? "Select items to remove" : "Remove \(picked.count) from \(scope == .wanted ? "wishlist" : "collection")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.isEmpty)
                } else {
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
        }
        .padding(12)
        .background(.bar)
    }
}
