import SwiftUI

// `Color.accent{Gold,Green,Red,Blue,Purple,Orange,Mint}` are Xcode-generated
// from `Assets.xcassets/Accent*.colorset` (asset symbol generation — no
// manual extension needed/allowed, colliding with one is a build error).
// Stand-ins for the plain system colors wherever used as *text or icon*
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
//
// Extended 2026-09-14: gold/green/red were tuned against the *page*
// background, but badges render their color as text *on that same color's
// own `.opacity(0.18)` capsule* — a harder, different contrast target.
// Sampled real rendered pixels for every badge color against its own wash
// (CompletenessBadge/StatusBadge's `.blue`/`.purple`, ConditionLabel's
// `.orange`/`.mint` dots, and re-checked gold/green/red) and found *all
// seven* fell short of 4.5:1 in that specific context — some badly (plain
// `.orange`/`.mint` measured ~1.6-1.7:1). Retuned gold/green/red's light
// value darker and added `AccentBlue`/`AccentPurple`/`AccentOrange`/
// `AccentMint` the same way, all targeting ~5.2:1 against their own wash.
//
// The retuned colors are real, independent improvements (verified by
// sampling actual rendered pixels post-fix, not just trusting the math) —
// but re-running the OS audit afterward, "CIB" (`AccentGreen`, genuinely
// darker now) is **still** flagged "Contrast failed", identical to what
// happened with `PlatformBreakdownCard`'s header text (see
// `AccessibilityAuditTests`'s doc comment): a verified, correctly-darker
// color that the live audit doesn't register as fixed. Two independent
// cases now, in unrelated visual contexts (plain background there, a
// same-hue tinted wash here) — real evidence `performAccessibilityAudit()`'s
// contrast check isn't simply measuring the current static-frame composited
// pixel color the way a screenshot sample does. Kept these fixes regardless
// (genuinely better contrast against the badge's own wash, verified by
// pixel-sampling, is correct on its own merits) but stopped chasing exact
// colorimetric values to satisfy this specific automated check — that needs
// either Xcode's interactive Accessibility Inspector or a better
// understanding of the audit's real algorithm, not more guessing.

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
        case .sealed, .graded: .accentPurple
        case .completeInBox: .accentGreen
        case .boxedNoManual: .accentBlue
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
        case .veryGood: .accentMint
        case .good: .accentGold
        case .fair: .accentOrange
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
        case .forSale: .accentBlue
        case .forTrade: .accentPurple
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
