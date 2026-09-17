import Foundation
import SwiftData

/// Mirrors `CollectionActions`: the single place a custom catalog row gets
/// created, so the sheet UI stays a thin form.
@MainActor
enum CustomCatalogItemActions {
    /// Creates the row on Supabase first, then inserts the matching local
    /// `CatalogItem` from what the server actually stored — no optimistic
    /// local insert before the round-trip succeeds, since there's no offline
    /// queue here (unlike `CollectionItem`) to reconcile a later failure
    /// against; local and remote must agree, not diverge.
    @discardableResult
    static func create(
        _ draft: CustomCatalogItemService.Draft,
        platform: Platform?,
        in context: ModelContext,
        service: CustomCatalogItemService = CustomCatalogItemService()
    ) async throws -> CatalogItem {
        let feedItem = try await service.create(draft)

        let item = CatalogItem(
            slug: feedItem.slug,
            kind: ItemKind(rawValue: feedItem.kind) ?? draft.kind,
            name: feedItem.name,
            variant: feedItem.variant,
            releaseYearNA: feedItem.releaseYearNA,
            manufacturerOrPublisher: feedItem.manufacturerOrPublisher,
            developer: feedItem.developer,
            genre: feedItem.genre,
            upc: feedItem.upc,
            summary: feedItem.summary ?? ""
        )
        item.ownerUserID = feedItem.ownerUserID
        item.platform = platform
        context.insert(item)
        context.saveLoggingErrors(reportingAs: .localSave)
        return item
    }
}
