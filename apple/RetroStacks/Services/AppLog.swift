import Foundation
import SwiftData
import os

/// Structured logging, viewable in Console.app / `xcrun simctl spawn <device>
/// log stream` filtered to subsystem `com.levidahlstrom.RetroStacks` — not a
/// substitute for `AppStatusCenter` (which is user-facing), but a permanent
/// record of exactly what a failed request/keychain call/decode returned.
///
/// Added 2026-09-13 after a silent `try?` around a JSON decode hid a real bug
/// (`SupabaseSession`'s `userID` field failing to round-trip through
/// `convertFromSnakeCase`) for as long as nothing was watching. The rule this
/// codifies: every non-2xx HTTP response and every non-`errSecSuccess`
/// Keychain status gets logged here, at minimum, even when it's also
/// surfaced to the user via `AppStatusCenter` or rethrown to the caller.
nonisolated enum AppLog {
    static let network = Logger(subsystem: "com.levidahlstrom.RetroStacks", category: "network")
    static let sync = Logger(subsystem: "com.levidahlstrom.RetroStacks", category: "sync")
    static let auth = Logger(subsystem: "com.levidahlstrom.RetroStacks", category: "auth")
    static let persistence = Logger(subsystem: "com.levidahlstrom.RetroStacks", category: "persistence")
}

extension ModelContext {
    /// Saves and logs failures instead of the plain `try? save()` that was
    /// spread across every collection add/edit/delete call site — the same
    /// silent-failure shape `AppLog`'s own header warns about, just never
    /// applied to local SwiftData writes. A disk-full, migration, or
    /// constraint error at these call sites previously vanished with nothing
    /// to show for it, at exactly the write paths a real user hits
    /// constantly. Not `throws` — callers weren't handling the error before
    /// either, so this keeps every call site's behavior identical and only
    /// adds the log record.
    ///
    /// `reportingAs`: pass an `AppStatusCenter.Source` to also surface a
    /// failure as a visible badge, not just a log line — reserved for
    /// user-initiated writes (adding/editing/removing a collection item)
    /// where staying silent would leave someone wondering whether their tap
    /// actually did anything. Left `nil` (the default) for background writes
    /// — catalog sync, pricing refresh, seed store — that already have their
    /// own more specific reporting, so they don't get double-counted under a
    /// generic "Save" badge.
    @discardableResult
    func saveLoggingErrors(reportingAs source: AppStatusCenter.Source? = nil) -> Bool {
        do {
            try save()
            if let source { AppStatusCenter.shared.clear(source) }
            return true
        } catch {
            AppLog.persistence.error("modelContext.save() failed: \(error, privacy: .public)")
            if let source {
                AppStatusCenter.shared.report(
                    source, severity: .error,
                    title: "Couldn't save your change",
                    detail: error.localizedDescription
                )
            }
            return false
        }
    }
}
