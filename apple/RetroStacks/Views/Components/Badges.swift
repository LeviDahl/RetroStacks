import SwiftUI

// `Color.accentGold`/`.accentGreen`/`.accentRed` are Xcode-generated from
// `Assets.xcassets/Accent{Gold,Green,Red}.colorset` (asset symbol generation
// — no manual extension needed/allowed, colliding with one is a build error).
// Stand-ins for `.yellow`/`.green`/`.red` wherever used as *text or icon*
// color (condition/status dots, badges, gain/loss figures) rather than a
// purely decorative fill: a darker shade in light mode, the system color's
// own dark-mode value in dark mode (unchanged there).
//
// Found 2026-09-13 doing the accessibility contrast pass — first on
// `.yellow` (StatusBadge's wishlist case measured ~1.4:1 in light mode,
// computed from the actual composited sRGB values via the WCAG
// relative-luminance formula, badly under the 3:1 UI-component floor let
// alone 4.5:1 for text), then confirmed by the OS's own
// `performAccessibilityAudit()` catching `.green` failing too (StatTile's
// "+$472 vs. invested" footnote). `.red` measured borderline (~3.55:1,
// passes 3:1 but not 4.5:1) and got the same treatment for consistency,
// since it's always paired with `.green` in gain/loss text. Dark mode was
// fine for all three already — yellow/green/red-on-light is the classic WCAG
// failure shape, not dark mode.

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
        case .completeInBox: .accentGreen
        case .boxedNoManual: .blue
        case .loose: .mutedText
        case .none: .mutedText
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
            .foregroundStyle(.mutedText)
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
        case .sealed, .mint: .accentGreen
        case .veryGood: .mint
        case .good: .accentGold
        case .fair: .orange
        case .poor: .accentRed
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
        case .owned: .accentGreen
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
            .foregroundStyle(.mutedText)
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
