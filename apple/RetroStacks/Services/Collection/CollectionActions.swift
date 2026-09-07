import Foundation
import SwiftData

/// The single place collection rows are created / removed. Keeping it here (not
/// scattered through views) means Phase 1 sync can hook every mutation in one
/// spot — and the add/quick-add UX stays consistent.
@MainActor
enum CollectionActions {
    /// Add a catalog item to the collection (or wishlist). Sensible defaults for
    /// an owned physical copy; no-ops if a live entry with that status exists.
    @discardableResult
    static func add(
        _ catalogItem: CatalogItem,
        status: CollectionStatus = .owned,
        in context: ModelContext
    ) -> CollectionItem {
        if let existing = catalogItem.entry(for: status) { return existing }
        let entry = CollectionItem(
            catalogItem: catalogItem,
            status: status,
            condition: status == .owned ? .good : nil,
            completeness: status == .owned ? .loose : nil,
            playStatus: catalogItem.kind == .game && status == .owned ? .backlog : nil
        )
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Soft-delete (tombstone) a collection entry so the removal can sync later.
    static func remove(_ item: CollectionItem, in context: ModelContext) {
        item.markDeleted()
        try? context.save()
    }
}
