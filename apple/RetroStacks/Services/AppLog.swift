import Foundation
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
}
