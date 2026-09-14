import SwiftUI

/// One switch for how de-emphasized metadata text (item counts, dates,
/// publishers, badge subtitles, footnotes — anything currently styled
/// `.secondary` at a small size) reads across the whole app.
///
/// The OS accessibility audit (`AccessibilityAuditTests` and friends in
/// `RetroStacksUITests/NavigationTests.swift`) flags `.subtle`'s look as
/// below the 4.5:1 WCAG contrast floor for small text in light mode —
/// confirmed systemic across Dashboard, SystemGamesList, CollectionSection,
/// and CatalogSection, not a one-screen bug. Kept as `.subtle` on purpose
/// (2026-09-14, user's call): every call site in `Views/` already goes
/// through `Color.mutedText` instead of hardcoding `.secondary` directly, so
/// flipping `current` to `.compliant` below — one line — is the entire fix
/// if this ever needs to change for a real compliance requirement or a user
/// complaint. No hunting through screens.
enum MutedTextStyle {
    case subtle
    case compliant

    static let current: MutedTextStyle = .subtle
}

extension ShapeStyle where Self == Color {
    /// Use for de-emphasized metadata text instead of `.secondary` directly
    /// — see `MutedTextStyle`. Declared on `ShapeStyle` (not a plain `Color`
    /// extension) so `.foregroundStyle(.mutedText)`'s dot-shorthand resolves
    /// the same way SwiftUI's own `.secondary`/`.red`/etc. do, in every
    /// call-site shape (chained modifiers, ternaries against other statics,
    /// inside `Label`/`HStack` builders) — a plain `Color` extension resolved
    /// in most places but not all of them.
    ///
    /// `.compliant`'s dark-mode value is an approximation of the system
    /// `secondaryLabel` dark tone (already measured as passing contrast,
    /// unlike light mode) — re-verify by real pixel sampling, the same way
    /// `AccentGold`/`.accentGreen`/`.accentRed` were tuned, before actually
    /// shipping `.compliant` for real; it's untested since `.subtle` is what
    /// every build has rendered so far.
    static var mutedText: Color {
        switch MutedTextStyle.current {
        case .subtle: .secondary
        case .compliant: Color("MutedTextCompliant")
        }
    }
}
