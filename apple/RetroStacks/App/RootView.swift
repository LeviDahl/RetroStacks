import SwiftUI
import SwiftData

/// App shell. macOS / iPadOS get a sidebar-driven split layout; iPhone (compact
/// width) gets a tab bar. Each section owns its own list↔detail split so the
/// desktop layout is genuinely three columns, not a stretched single column.
struct RootView: View {
    @State private var selection: AppSection = .dashboard

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        layout
            .overlay(alignment: .bottomTrailing) {
                AppStatusBadge()
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            tabLayout
        } else {
            splitLayout
        }
        #else
        splitLayout
        #endif
    }

    private var splitLayout: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            sectionView(for: selection)
        }
    }

    private var tabLayout: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                tabContent(for: section)
                    .tabItem { Label(section.tabTitle, systemImage: section.symbol) }
                    .tag(section)
            }
        }
    }

    /// On iPhone the split sections collapse to their own stack, so only the
    /// plain Dashboard needs an explicit `NavigationStack` wrapper.
    @ViewBuilder
    private func tabContent(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            NavigationStack { DashboardView(onSelectSection: { selection = $0 }) }
        default:
            sectionView(for: section)
        }
    }

    @ViewBuilder
    private func sectionView(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView(onSelectSection: { selection = $0 })
        case .collection:
            CollectionSection(mode: .collection)
        case .wishlist:
            CollectionSection(mode: .wishlist)
        case .catalog:
            CatalogSection()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
}
