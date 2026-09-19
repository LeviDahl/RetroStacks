import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: AppSection

    @Query(filter: #Predicate<CollectionItem> { $0.deletedAt == nil })
    private var collectionItems: [CollectionItem]

    /// `List` on iOS only offers the optional-selection initializer; bridge the
    /// non-optional binding through so the sidebar compiles on every platform.
    private var listSelection: Binding<AppSection?> {
        Binding(get: { selection }, set: { selection = $0 ?? selection })
    }

    var body: some View {
        List(selection: listSelection) {
            Section {
                row(.dashboard)
                row(.collection, badge: ownedCount)
                row(.wishlist, badge: wishlistCount)
            }

            Section("Discover") {
                row(.catalog)
            }
        }
        .navigationTitle("RetroStacks")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        #endif
        .listStyle(.sidebar)
    }

    private func row(_ section: AppSection, badge: Int? = nil) -> some View {
        // Manual icon+Text, not `Label(...)` — mirrors the fix already
        // proven in `DashboardView`'s `BreakdownBar` header: `Label` was
        // found (by sampling actual rendered pixels) to render its title
        // visibly lighter than a plain `Text` at the same
        // `.foregroundStyle(.primary)`, a genuine rendering bug independent
        // of the OS accessibility audit's separate, still-unexplained
        // "Contrast failed" findings on this same row shape (see
        // AccessibilityAuditTests's doc comment for the fuller account).
        HStack(spacing: 6) {
            Image(systemName: section.symbol)
                .accessibilityHidden(true) // decorative — Text carries the label, same as Label(...) would
            Text(section.title)
        }
        .badge(badge ?? 0)
        .tag(section)
        .accessibilityIdentifier(AccessibilityID.Sidebar.item(section))
    }

    private var ownedCount: Int {
        collectionItems.filter { $0.status == .owned }.count
    }
    private var wishlistCount: Int {
        collectionItems.filter { $0.status == .wishlist }.count
    }
}

#Preview {
    @Previewable @State var selection: AppSection = .dashboard
    NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        Text(selection.title)
    }
    .modelContainer(SampleData.previewContainer())
}
