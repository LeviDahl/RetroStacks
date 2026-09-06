import SwiftUI

/// Top-level sections, shown as the sidebar on macOS/iPadOS and as tabs on iPhone.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case collection
    case wishlist
    case catalog
    case platforms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .collection: "My Collection"
        case .wishlist: "Wishlist"
        case .catalog: "Browse Catalog"
        case .platforms: "Platforms"
        }
    }

    /// Shorter label for the iPhone tab bar.
    var tabTitle: String {
        switch self {
        case .dashboard: "Home"
        case .collection: "Collection"
        case .wishlist: "Wishlist"
        case .catalog: "Catalog"
        case .platforms: "Systems"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "chart.bar.xaxis"
        case .collection: "square.grid.2x2"
        case .wishlist: "star"
        case .catalog: "books.vertical"
        case .platforms: "gamecontroller"
        }
    }
}
/// SwiftData `@Model` types are `Identifiable` + `Hashable`, so views navigate by
/// passing the model object itself as the `NavigationLink` / path value and
/// resolving it with `.navigationDestination(for: CatalogItem.self) { … }`.
