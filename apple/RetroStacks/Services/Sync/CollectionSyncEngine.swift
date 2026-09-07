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

/// The seam a real backend (Supabase / a custom API) implements. No engine is
/// connected yet — `Sync.engine` is `DisabledSyncEngine`.
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

/// Single swap point. Phase 1 changes this to the Supabase engine.
nonisolated enum Sync {
    static let engine: any CollectionSyncEngine = DisabledSyncEngine()
}
