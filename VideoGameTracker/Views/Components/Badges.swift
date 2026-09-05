import SwiftUI

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
        }
    }

    private var color: Color {
        switch condition {
        case .sealed, .mint: .green
        case .veryGood: .mint
        case .good: .yellow
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
        case .wishlist: .yellow
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
