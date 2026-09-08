import SwiftUI

/// The small corner icon that appears **only** when something failed in the
/// background. Tap it for the list of what went wrong, with per-issue Retry.
/// Nothing renders when there are no issues.
struct AppStatusBadge: View {
    @State private var center = AppStatusCenter.shared
    @State private var showingPanel = false

    private var tint: Color {
        switch center.worstSeverity {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }

    var body: some View {
        Group {
            if center.hasIssues {
                Button {
                    showingPanel.toggle()
                } label: {
                    Image(systemName: center.worstSeverity.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if center.issues.count > 1 {
                                Text("\(center.issues.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(tint)
                                    .padding(3)
                                    .background(.background, in: Circle())
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(center.issues.count) background \(center.issues.count == 1 ? "issue" : "issues")")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .popover(isPresented: $showingPanel) {
                    StatusPanel(center: center)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: center.issues)
    }
}

private struct StatusPanel: View {
    var center: AppStatusCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Background Issues").font(.headline)
                Spacer()
                if !center.issues.isEmpty {
                    Button("Dismiss All") { center.dismissAll() }
                        .font(.callout)
                }
            }
            .padding(12)

            Divider()

            if center.issues.isEmpty {
                Text("All clear.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(center.issues) { issue in
                            IssueRow(issue: issue, center: center)
                            if issue.id != center.issues.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 360)
        .presentationCompactAdaptation(.popover)
    }
}

private struct IssueRow: View {
    var issue: AppStatusCenter.Issue
    var center: AppStatusCenter

    private var tint: Color {
        switch issue.severity {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity.symbol)
                .foregroundStyle(tint)
                .font(.callout)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.callout.weight(.medium))
                if let detail = issue.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Text(issue.date, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let retry = issue.retry {
                        Button("Retry") {
                            center.dismiss(issue)
                            retry()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 4)

            Button {
                center.dismiss(issue)
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}

#Preview {
    let center = AppStatusCenter.shared
    center.report(.catalogSync, severity: .warning,
                  title: "Catalog didn't update",
                  detail: "Couldn't reach the data server. Showing the last synced copy.",
                  retry: {})
    center.report(.pricing, severity: .info,
                  title: "Couldn't refresh prices",
                  detail: "Showing the last known values.")
    return Color.gray.opacity(0.2)
        .overlay(alignment: .bottomTrailing) { AppStatusBadge().padding(24) }
}
