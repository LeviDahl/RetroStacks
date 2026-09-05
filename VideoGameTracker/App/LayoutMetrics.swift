import SwiftUI

/// Central place for the spacing / sizing differences between the roomy desktop
/// layout and the compact touch layout. The goal on macOS is to *use* the extra
/// width with multi-column grids and generous margins — never to stretch a
/// single iOS column across a 1400pt window.
enum LayoutMetrics {
    #if os(macOS)
    static let screenEdgePadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 32
    static let cardSpacing: CGFloat = 20
    static let cardCornerRadius: CGFloat = 14
    static let gridMinCardWidth: CGFloat = 260
    static let posterMinWidth: CGFloat = 180
    static let contentMaxWidth: CGFloat = .infinity
    static let usesTableForLists = true
    #else
    static let screenEdgePadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let cardSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12
    static let gridMinCardWidth: CGFloat = 320
    static let posterMinWidth: CGFloat = 150
    static let contentMaxWidth: CGFloat = 700
    static let usesTableForLists = false
    #endif

    /// Adaptive grid columns for card walls.
    static func cardColumns(spacing: CGFloat = cardSpacing) -> [GridItem] {
        [GridItem(.adaptive(minimum: gridMinCardWidth), spacing: spacing)]
    }

    /// Adaptive grid columns for poster/thumbnail walls.
    static func posterColumns(spacing: CGFloat = cardSpacing) -> [GridItem] {
        [GridItem(.adaptive(minimum: posterMinWidth), spacing: spacing)]
    }
}

extension View {
    /// Constrains reading-width content on iOS while letting macOS fill the pane.
    func readableContentColumn() -> some View {
        frame(maxWidth: LayoutMetrics.contentMaxWidth, alignment: .leading)
    }
}
