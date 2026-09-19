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
                    .padding(.bottom, statusBadgeBottomPadding)
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

    /// iPhone's tab bar floats as an inset capsule near the trailing edge, so a
    /// plain corner inset collides with its last item (confirmed in the
    /// simulator: it sat right on top of the "Catalog" label). Clear it there;
    /// the split layout has no tab bar to dodge.
    private var statusBadgeBottomPadding: CGFloat {
        #if os(iOS)
        horizontalSizeClass == .compact ? 88 : 16
        #else
        16
        #endif
    }

    /// Tried keeping all four sections mounted simultaneously (`ZStack` +
    /// opacity) 2026-09-19, to fix `AsyncImage` visibly reloading on every
    /// sidebar click (it re-runs its fetch/phase transition whenever its own
    /// view identity is recreated, which the destructive `switch` below
    /// does to the whole screen on every click, warm `URLCache` or not).
    /// **Reverted** — real live testing (`performAccessibilityAudit()` on
    /// iPad, where `splitLayout` actually runs, not the iPhone/`tabLayout`
    /// destination this suite otherwise uses) found the other three
    /// *hidden* sections' content — `CatalogSection`'s own description
    /// text, Wishlist's counts — leaking into a scan that should have been
    /// Dashboard-only (findings jumped 11 → 71). `.accessibilityHidden`
    /// didn't reliably suppress it. Confirming whether that's a real
    /// VoiceOver-facing regression or just this audit tool over-scanning
    /// (this codebase has already found real cases of the latter — see
    /// `BreakdownBar`'s contrast-check mystery) needed live Simulator
    /// inspection, which wasn't available this session (device access not
    /// yet granted). Rather than ship a real accessibility risk on a guess,
    /// reverted to the plain `switch` and fixed the actual reported
    /// symptom (images reloading) at its real source instead — see
    /// `ItemThumbnail`'s image cache.
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
                sectionView(for: section)
                    .tabItem { Label(section.tabTitle, systemImage: section.symbol) }
                    .tag(section)
            }
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
