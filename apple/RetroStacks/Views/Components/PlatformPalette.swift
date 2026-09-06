import SwiftUI

/// Stable per-platform accent colors for charts and accents. The color is keyed
/// to the platform `slug` via a deterministic hash, so a platform keeps the same
/// hue no matter how a list is sorted or filtered (unlike `String.hashValue`,
/// which is randomized per process).
enum PlatformPalette {
    /// Distinct, theme-adaptive hues. System colors so light/dark both read well.
    static let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint,
        .teal, .cyan, .blue, .indigo, .purple, .pink, .brown,
    ]

    static func color(for slug: String) -> Color {
        colors[stableIndex(slug, modulo: colors.count)]
    }

    /// djb2 — small, deterministic, good enough for bucketing.
    private static func stableIndex(_ string: String, modulo: Int) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) ^ UInt64(byte)
        }
        return Int(hash % UInt64(max(modulo, 1)))
    }
}
