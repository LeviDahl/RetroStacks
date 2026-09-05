import SwiftUI
import SwiftData

/// Registers every model-driven navigation destination once per navigation stack.
///
/// Apply this at the *root* of each detail column / `NavigationStack` rather than
/// scattering `.navigationDestination` through child views — a type may only be
/// registered once per stack.
extension View {
    func gameTrackerDestinations() -> some View {
        self
            .navigationDestination(for: CatalogItem.self) { CatalogItemDetailView(item: $0) }
            .navigationDestination(for: CollectionItem.self) { CollectionItemDetailView(item: $0) }
            .navigationDestination(for: Platform.self) { PlatformDetailView(platform: $0) }
    }
}
