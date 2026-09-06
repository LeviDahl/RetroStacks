import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: AppSection

    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \Platform.generation) private var platforms: [Platform]

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
                row(.platforms, badge: platforms.count)
            }
        }
        .navigationTitle("Game Tracker")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        #endif
        .listStyle(.sidebar)
    }

    private func row(_ section: AppSection, badge: Int? = nil) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(badge ?? 0)
            .tag(section)
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
    return NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        Text(selection.title)
    }
    .modelContainer(SampleData.previewContainer())
}
