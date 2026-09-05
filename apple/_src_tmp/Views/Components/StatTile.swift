import SwiftUI

struct StatTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = .accentColor
    var footnote: String? = nil
    var footnoteColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(footnoteColor)
                    .lineLimit(1)
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

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
        StatTile(title: "Owned Items", value: "128", systemImage: "square.grid.2x2", tint: .indigo, footnote: "8 added this month")
        StatTile(title: "Est. Value", value: "$4,210", systemImage: "chart.line.uptrend.xyaxis", tint: .green, footnote: "+$960 vs. invested", footnoteColor: .green)
        StatTile(title: "Invested", value: "$3,250", systemImage: "creditcard", tint: .blue)
    }
    .padding()
}
