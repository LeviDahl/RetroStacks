import Foundation
import Observation
import SwiftData

/// Runs `Sync.engine` against the local `CollectionItem` store: pull, resolve
/// conflicts last-write-wins by `updatedAt`, push whatever's still locally
/// dirty, settle authoritative timestamps back. Mirrors `CatalogSyncService`'s
/// shape (phase, `retry()`, `AppStatusCenter` reporting) so the two read the
/// same to anyone touching this code later.
///
/// No-ops entirely while signed out or `Sync.engine.isEnabled == false` — the
/// app stays fully local-first; this only ever adds behavior, never requires it.
@MainActor
@Observable
final class SyncCoordinator {
    enum Phase: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var lastContext: ModelContext?

    private let engine: any CollectionSyncEngine
    private let isSignedIn: @MainActor () -> Bool
    private let defaults: UserDefaults

    static let shared = SyncCoordinator()

    /// Real dependencies for app use. Tests construct their own instance with
    /// a fake engine, a stub sign-in check, and a scratch `UserDefaults` suite
    /// so `lastSyncedAt` bookkeeping doesn't leak between test cases.
    init(
        engine: any CollectionSyncEngine = Sync.engine,
        isSignedIn: @escaping @MainActor () -> Bool = { AccountService.shared.state.isSignedIn },
        defaults: UserDefaults = .standard
    ) {
        self.engine = engine
        self.isSignedIn = isSignedIn
        self.defaults = defaults
    }

    private let lastSyncedKey = "sync.collectionLastSyncedAt"
    private var lastSyncedAt: Date? {
        get {
            let interval = defaults.double(forKey: lastSyncedKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: lastSyncedKey)
            } else {
                defaults.removeObject(forKey: lastSyncedKey)
            }
        }
    }

    func retry() {
        guard let context = lastContext else { return }
        Task { await sync(into: context) }
    }

    /// Safe to call any time (sign-in, app foreground, a manual "Sync now") —
    /// it's a no-op when there's nothing to do and won't overlap itself.
    func sync(into context: ModelContext) async {
        guard isSignedIn(), engine.isEnabled else { return }
        guard phase != .syncing else { return }
        lastContext = context
        phase = .syncing
        do {
            try await runSync(context: context)
            phase = .synced(.now)
            AppStatusCenter.shared.clear(.collectionSync)
        } catch {
            phase = .failed(String(describing: error))
            let message = (error as? SyncError)?.description ?? error.localizedDescription
            AppStatusCenter.shared.report(
                .collectionSync,
                severity: .warning,
                title: "Collection didn’t sync",
                detail: "\(message) Your local changes are safe.",
                retry: { SyncCoordinator.shared.retry() }
            )
        }
    }

    // MARK: - The actual pull/resolve/push

    private func runSync(context: ModelContext) async throws {
        let since = lastSyncedAt
        let remoteChanges = try await engine.pull(since: since)

        let localItems = try context.fetch(FetchDescriptor<CollectionItem>())
        let localByID = Dictionary(localItems.map { ($0.resolvedExportID, $0) }, uniquingKeysWith: { a, _ in a })
        let catalogBySlug = Dictionary(
            try context.fetch(FetchDescriptor<CatalogItem>()).map { ($0.slug, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        // Remote changes: apply the ones that are newer than what's local
        // (last-write-wins); a local item that's newer just keeps going —
        // it'll get pushed below instead. New remote items with no local
        // counterpart are inserted.
        var justAppliedFromRemote = Set<UUID>()
        for change in remoteChanges {
            if let existing = localByID[change.exportID] {
                guard change.updatedAt > existing.updatedAt else { continue }
                apply(change, to: existing, catalogBySlug: catalogBySlug)
                justAppliedFromRemote.insert(change.exportID)
            } else {
                let item = CollectionItem(dateAdded: change.payload?.dateAdded ?? change.updatedAt, exportID: change.exportID)
                context.insert(item)
                apply(change, to: item, catalogBySlug: catalogBySlug)
                justAppliedFromRemote.insert(change.exportID)
            }
        }

        // Local changes since the last sync, minus whatever remote just won —
        // pushing those back would just re-assert what we already overwrote.
        let sinceOrEpoch = since ?? .distantPast
        let dirty = localItems.filter {
            $0.updatedAt > sinceOrEpoch && !justAppliedFromRemote.contains($0.resolvedExportID)
        }
        if !dirty.isEmpty {
            let changes = dirty.map(CollectionChange.from)
            let authoritative = try await engine.push(changes)
            let authoritativeByID = Dictionary(authoritative.map { ($0.exportID, $0) }, uniquingKeysWith: { a, _ in a })
            for item in dirty {
                if let settled = authoritativeByID[item.resolvedExportID] {
                    item.updatedAt = settled.updatedAt
                }
            }
        }

        if context.hasChanges { try context.save() }
        lastSyncedAt = .now
    }

    private func apply(_ change: CollectionChange, to item: CollectionItem, catalogBySlug: [String: CatalogItem]) {
        if let payload = change.payload {
            payload.apply(to: item, catalogBySlug: catalogBySlug)
        }
        item.deletedAt = change.deletedAt
        item.updatedAt = change.updatedAt
    }
}
