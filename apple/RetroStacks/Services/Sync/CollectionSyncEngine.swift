import Foundation

/// One change to push up or apply down, keyed by `CollectionItem.exportID`.
/// An upsert carries `payload`; a `deletedAt != nil` change with `payload == nil`
/// is a pure tombstone. Reuses `CollectionArchive.Entry` as the row format so
/// there's one serialization to maintain.
nonisolated struct CollectionChange: Sendable, Codable {
    var exportID: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var payload: CollectionArchive.Entry?
}

extension CollectionChange {
    /// Always carries a full `payload` — a locally soft-deleted `CollectionItem`
    /// still has every field, and the server row's `NOT NULL` columns need them
    /// regardless of `deletedAt` (see `supabase/schema.sql`).
    @MainActor
    static func from(_ item: CollectionItem) -> CollectionChange {
        CollectionChange(
            exportID: item.resolvedExportID,
            updatedAt: item.updatedAt,
            deletedAt: item.deletedAt,
            payload: CollectionArchive.Entry(item: item)
        )
    }
}

/// The seam a real backend (Supabase / a custom API) implements —
/// `SupabaseCollectionSyncEngine` is the one `Sync.engine` actually points at
/// (see the bottom of this file); `DisabledSyncEngine` below stays as the
/// local-first fallback shape and for tests that don't want real network/
/// Keychain calls.
nonisolated protocol CollectionSyncEngine: Sendable {
    var isEnabled: Bool { get }

    /// Server changes since `date` (nil = full snapshot). Requires a signed-in user.
    func pull(since date: Date?) async throws -> [CollectionChange]

    /// Push local changes; returns the server's authoritative versions
    /// (so the client can settle `updatedAt` and detect conflicts).
    func push(_ changes: [CollectionChange]) async throws -> [CollectionChange]
}

nonisolated struct DisabledSyncEngine: CollectionSyncEngine {
    var isEnabled: Bool { false }
    func pull(since date: Date?) async throws -> [CollectionChange] { [] }
    func push(_ changes: [CollectionChange]) async throws -> [CollectionChange] {
        throw SyncError.notSignedIn
    }
}

nonisolated enum SyncError: Error, CustomStringConvertible {
    case notSignedIn
    case notConfigured
    case conflict(exportID: UUID)
    case transport(String)

    var description: String {
        switch self {
        case .notSignedIn: "Not signed in."
        case .notConfigured: "Sync isn't set up yet."
        case .conflict(let id): "Sync conflict on \(id)."
        case .transport(let m): "Network error: \(m)"
        }
    }
}

/// Single swap point.
nonisolated enum Sync {
    static let engine: any CollectionSyncEngine = SupabaseCollectionSyncEngine()
}
