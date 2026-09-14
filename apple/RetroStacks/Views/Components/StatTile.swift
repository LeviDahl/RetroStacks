import SwiftUI

struct StatTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = .accentColor
    var footnote: String?
    var footnoteColor: Color = .mutedText
    /// When set, the whole tile becomes a button (e.g. "Owned Items" → My Collection).
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(TileButtonStyle())
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.mutedText)
                    .labelStyle(.titleAndIcon)
                if action != nil {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true) // decorative affordance — the tile is already a button
                }
            }

            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let footnote {
                // .minimumScaleFactor added 2026-09-13 — the accessibility
                // audit flagged this as "may be clipped at larger Dynamic
                // Type sizes" (lineLimit(1) with nothing to shrink it).
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(footnoteColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }
}

/// Subtle press feedback for tappable tiles/cards — scale + fade, no extra chrome.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
        StatTile(title: "Owned Items", value: "128", systemImage: "square.grid.2x2", tint: .indigo, footnote: "8 added this month")
        StatTile(
            title: "Est. Value", value: "$4,210", systemImage: "chart.line.uptrend.xyaxis",
            tint: .green, footnote: "+$960 vs. invested", footnoteColor: .green
        )
        StatTile(title: "Invested", value: "$3,250", systemImage: "creditcard", tint: .blue)
    }
    .padding()
}
