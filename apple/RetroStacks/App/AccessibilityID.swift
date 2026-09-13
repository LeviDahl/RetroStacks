import Foundation

/// Centralized, stable identifiers for `.accessibilityIdentifier(_:)` —
/// consumed by `RetroStacksUITests` (via `@testable import`) and, eventually,
/// VoiceOver tooling. Namespaced per feature folder, mirroring `Views/<Feature>/`.
///
/// Two shapes:
/// - **Static** ids for one-off chrome (`Dashboard.ownedItemsTile`).
/// - **Keyed** ids for repeated content, built from the model's own durable
///   identity — never array position — so a resort/filter/reorder never
///   changes what a row is addressed as (`Dashboard.breakdownRow(platform.slug)`).
///
/// Bootstrapped minimally: only what `NavigationTests` needs today, because
/// text-based UI-test queries turned out to be unreliable — SwiftUI collapses
/// a `Button`/`NavigationLink`'s child `Text` into one opaque accessibility
/// element, so `app.staticTexts["SNES"]` never existed to find (this is also
/// what the accessibility audit's "Parent/Child mismatch" finding is about).
/// Extend this file as the rest of `BACKLOG.md`'s Accessibility item gets
/// picked up — same shape, more cases.
enum AccessibilityID {
    enum Sidebar {
        /// Keyed by `AppSection.rawValue` — already a stable string ("dashboard",
        /// "collection", …), not the row's position in the list.
        static func item(_ section: AppSection) -> String {
            "sidebar.\(section.rawValue)"
        }
    }

    enum Dashboard {
        static let ownedItemsTile = "dashboard.ownedItemsTile"

        static func breakdownRow(_ platformSlug: String) -> String {
            "dashboard.breakdownRow.\(platformSlug)"
        }
    }
}
