import SwiftUI

/// A non-blocking, auto-dismissing banner — for FYI-only outcomes ("Exported
/// 12 items") that don't need a tap to acknowledge, unlike an `alert`. Added
/// 2026-09-13 per the tap-friction audit: several flows ended their success
/// path on a plain `alert` whose only button was "OK," which is pure
/// friction — a decision-less tap. Real failures should still use a blocking
/// `alert`; this is only for the happy path (or for showing an "Undo" on
/// something that already happened, e.g. a swipe-to-delete).
private struct ToastModifier: ViewModifier {
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: () -> Void

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    HStack(spacing: 14) {
                        Text(message)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                        if let actionTitle, let action {
                            Button(actionTitle) {
                                dismissTask?.cancel()
                                action()
                                onDismiss()
                            }
                            .font(.callout.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.snappy(duration: 0.25), value: message)
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                let seconds: Double = actionTitle != nil ? 4 : 2.2
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    if !Task.isCancelled { onDismiss() }
                }
            }
    }
}

extension View {
    /// Shows `message` as an auto-dismissing bottom banner while it's
    /// non-nil. Pass `actionTitle`/`action` to add an "Undo"-style button,
    /// which extends the auto-dismiss window since there's now something to
    /// read and decide on.
    func toast(
        _ message: String?,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(ToastModifier(message: message, actionTitle: actionTitle, action: action, onDismiss: onDismiss))
    }
}
