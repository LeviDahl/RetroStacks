import Foundation
import Observation

/// App-wide collector for background failures that would otherwise be silent —
/// a failed catalog sync, prices that couldn't refresh, later a sync-engine
/// error. The UI surface is one small badge in a window corner
/// (`AppStatusBadge`); this type is the model behind it.
///
/// Rules that keep it from being noisy:
/// - one live issue per `Source` (a new report replaces the old one, never stacks)
/// - `clear(_:)` on the next success removes the issue and hides the badge
/// - nothing here ever presents an alert or a sheet on its own
@MainActor
@Observable
final class AppStatusCenter {
    static let shared = AppStatusCenter()
    init() {}

    enum Severity: Int, Comparable {
        case info, warning, error
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "exclamationmark.octagon.fill"
            }
        }
    }

    /// One slot per source of trouble.
    enum Source: String, CaseIterable {
        case catalogSync, pricing, collectionSync, account

        var label: String {
            switch self {
            case .catalogSync: "Catalog sync"
            case .pricing: "Pricing"
            case .collectionSync: "Collection sync"
            case .account: "Account"
            }
        }
    }

    struct Issue: Identifiable, Equatable {
        let id = UUID()
        var source: Source
        var severity: Severity
        var title: String
        var detail: String?
        var date: Date
        /// Optional one-tap recovery. Not stored in `Equatable`.
        var retry: (@MainActor () -> Void)?

        static func == (lhs: Issue, rhs: Issue) -> Bool { lhs.id == rhs.id }
    }

    /// Newest first, at most one per `Source`.
    private(set) var issues: [Issue] = []

    var hasIssues: Bool { !issues.isEmpty }
    var worstSeverity: Severity { issues.map(\.severity).max() ?? .info }

    // MARK: - Producers call these

    func report(
        _ source: Source,
        severity: Severity = .error,
        title: String,
        detail: String? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        var next = issues.filter { $0.source != source }
        next.insert(
            Issue(source: source, severity: severity, title: title,
                  detail: detail, date: .now, retry: retry),
            at: 0
        )
        issues = next
    }

    /// Call on the next success for this source — removes its issue (and the
    /// badge, if it was the only one).
    func clear(_ source: Source) {
        guard issues.contains(where: { $0.source == source }) else { return }
        issues.removeAll { $0.source == source }
    }

    // MARK: - The badge UI calls these

    func dismiss(_ issue: Issue) { issues.removeAll { $0.id == issue.id } }
    func dismissAll() { issues.removeAll() }
}
