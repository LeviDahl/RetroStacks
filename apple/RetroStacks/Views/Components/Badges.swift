import SwiftUI

// `Color.accentGold` is Xcode-generated from `Assets.xcassets/AccentGold.colorset`
// (asset symbol generation, no manual extension needed/allowed — colliding
// with one is a build error). Stand-in for `.yellow` wherever it's used as
// *text or icon* color (condition/status dots, badges, wishlist stars)
// rather than a purely decorative fill: a dark amber (#785600) in light
// mode, the standard systemYellow dark value (#FFD60A) in dark mode.
//
// Found 2026-09-13 doing the accessibility contrast pass: plain `.yellow`
// text/icon on its usual pale-yellow wash background measured **~1.4:1** in
// light mode (computed from the actual composited sRGB values, WCAG
// relative-luminance formula) — badly under the 3:1 floor for UI components,
// let alone 4.5:1 for text. `.yellow` in *dark* mode was already fine
// (~6.1:1) — yellow-on-light is the classic WCAG failure case, dark mode
// wasn't the problem. `#785600` gets back to ~5.3:1 in light mode while
// staying legible as "gold" (not brown), and dark mode is untouched (still
// systemYellow's own dark value).

/// Small pill used for completeness (CIB / LOOSE / SEALED …).
struct CompletenessBadge: View {
    var completeness: Completeness?

    var body: some View {
        if let completeness {
            Text(completeness.shortName)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch completeness {
        case .sealed, .graded: .purple
        case .completeInBox: .green
        case .boxedNoManual: .blue
        case .loose: .secondary
        case .none: .secondary
        }
    }
}

/// Condition shown as a filled dot + label.
struct ConditionLabel: View {
    var condition: ConditionGrade?
    var compact: Bool = false

    var body: some View {
        if let condition {
            Label {
                if !compact { Text(condition.displayName) }
            } icon: {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            // In `compact` mode the title `Text` is omitted entirely (just the
            // dot) — without this, VoiceOver gets nothing at all for condition,
            // since a plain `Circle` carries no accessible text on its own.
            // Set unconditionally (not just when compact) since it's the same
            // text the visible title would show anyway.
            .accessibilityLabel(condition.displayName)
        }
    }

    private var color: Color {
        switch condition {
        case .sealed, .mint: .green
        case .veryGood: .mint
        case .good: .accentGold
        case .fair: .orange
        case .poor: .red
        case .none: .secondary
        }
    }
}

struct StatusBadge: View {
    var status: CollectionStatus

    var body: some View {
        Label(status.displayName, systemImage: status.symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .owned: .green
        case .wishlist: .accentGold
        case .forSale: .blue
        case .forTrade: .purple
        }
    }
}

struct KindTag: View {
    var kind: ItemKind
    var body: some View {
        Label(kind.displayName, systemImage: kind.symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HStack { CompletenessBadge(completeness: .completeInBox); CompletenessBadge(completeness: .loose); CompletenessBadge(completeness: .sealed) }
        ConditionLabel(condition: .veryGood)
        HStack { StatusBadge(status: .owned); StatusBadge(status: .wishlist); StatusBadge(status: .forSale) }
        KindTag(kind: .console)
    }
    .padding()
}
