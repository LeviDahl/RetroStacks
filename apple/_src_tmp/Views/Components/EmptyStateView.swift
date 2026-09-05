import SwiftUI

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    EmptyStateView(
        title: "No Games Yet",
        message: "Add a game from the catalog to start tracking it.",
        systemImage: "opticaldiscdrive",
        actionTitle: "Browse Catalog",
        action: {}
    )
}
