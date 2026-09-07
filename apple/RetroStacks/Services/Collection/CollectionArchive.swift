import Foundation
import SwiftData

/// A portable snapshot of the user's collection — the backup format. Everything
/// needed to rebuild `CollectionItem`s is here; catalog items are referenced by
/// `catalogSlug` and re-linked on import (an entry whose slug isn't in the
/// catalog still imports, just unlinked, and links itself once catalog sync
/// brings that slug in).
nonisolated struct CollectionArchive: Codable, Sendable {
    var format = "retrostacks.collection"
    var version = 1
    var exportedAt = Date()
    var itemCount: Int { entries.count }
    var entries: [Entry]

    nonisolated struct Entry: Codable, Sendable {
        var exportID: UUID
        var catalogSlug: String?
        var catalogName: String?          // human-readable; not used on import
        var platformShortName: String?

        var status: String
        var condition: String?
        var completeness: String?
        var hasBox: Bool
        var hasManual: Bool
        var hasInserts: Bool
        var hasOriginalPackaging: Bool
        var gradingCompany: String
        var gradeScore: Double?
        var pricePaid: Decimal?
        var dateAcquired: Date?
        var acquisitionSource: String?
        var estimatedValueOverride: Decimal?
        var storageLocation: String?
        var notes: String
        var playStatus: String?
        var dateAdded: Date
        var updatedAt: Date?          // absent in v1 archives
        var photosBase64: [String]
    }

    enum ImportMode { case merge, replace }

    // MARK: - Export

    @MainActor
    static func make(from items: [CollectionItem]) -> CollectionArchive {
        CollectionArchive(
            entries: items
                .filter { !$0.isDeleted }
                .sorted { $0.dateAdded < $1.dateAdded }
                .map { item in
                    Entry(
                        exportID: item.resolvedExportID,
                        catalogSlug: item.catalogItem?.slug,
                        catalogName: item.catalogItem?.displayTitle,
                        platformShortName: item.catalogItem?.platformShortName,
                        status: item.status.rawValue,
                        condition: item.condition?.rawValue,
                        completeness: item.completeness?.rawValue,
                        hasBox: item.hasBox,
                        hasManual: item.hasManual,
                        hasInserts: item.hasInserts,
                        hasOriginalPackaging: item.hasOriginalPackaging,
                        gradingCompany: item.gradingCompany.rawValue,
                        gradeScore: item.gradeScore,
                        pricePaid: item.pricePaid,
                        dateAcquired: item.dateAcquired,
                        acquisitionSource: item.acquisitionSource?.rawValue,
                        estimatedValueOverride: item.estimatedValueOverride,
                        storageLocation: item.storageLocation,
                        notes: item.notes,
                        playStatus: item.playStatus?.rawValue,
                        dateAdded: item.dateAdded,
                        updatedAt: item.updatedAt,
                        photosBase64: item.photoData.map { $0.base64EncodedString() }
                    )
                }
        )
    }

    // MARK: - Import

    /// Returns (inserted, updated, deleted).
    @MainActor
    @discardableResult
    func restore(into context: ModelContext, mode: ImportMode) throws -> (Int, Int, Int) {
        let existing = try context.fetch(FetchDescriptor<CollectionItem>())
        var deleted = 0

        if mode == .replace {
            for item in existing { context.delete(item); deleted += 1 }
        }

        var byExportID: [UUID: CollectionItem] = mode == .replace
            ? [:]
            : Dictionary(existing.map { ($0.resolvedExportID, $0) }, uniquingKeysWith: { a, _ in a })

        let catalog = try context.fetch(FetchDescriptor<CatalogItem>())
        let catalogBySlug = Dictionary(catalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })

        var inserted = 0, updated = 0
        for entry in entries {
            let item: CollectionItem
            if let match = byExportID[entry.exportID] {
                item = match
                updated += 1
            } else {
                item = CollectionItem(status: .owned, dateAdded: entry.dateAdded, exportID: entry.exportID)
                context.insert(item)
                byExportID[entry.exportID] = item
                inserted += 1
            }

            item.catalogItem = entry.catalogSlug.flatMap { catalogBySlug[$0] }
            item.status = CollectionStatus(rawValue: entry.status) ?? .owned
            item.condition = entry.condition.flatMap(ConditionGrade.init(rawValue:))
            item.completeness = entry.completeness.flatMap(Completeness.init(rawValue:))
            item.hasBox = entry.hasBox
            item.hasManual = entry.hasManual
            item.hasInserts = entry.hasInserts
            item.hasOriginalPackaging = entry.hasOriginalPackaging
            item.gradingCompany = GradingCompany(rawValue: entry.gradingCompany) ?? .none
            item.gradeScore = entry.gradeScore
            item.pricePaid = entry.pricePaid
            item.dateAcquired = entry.dateAcquired
            item.acquisitionSource = entry.acquisitionSource.flatMap(AcquisitionSource.init(rawValue:))
            item.estimatedValueOverride = entry.estimatedValueOverride
            item.storageLocation = entry.storageLocation
            item.notes = entry.notes
            item.playStatus = entry.playStatus.flatMap(PlayStatus.init(rawValue:))
            item.dateAdded = entry.dateAdded
            item.photoData = entry.photosBase64.compactMap { Data(base64Encoded: $0) }
            item.deletedAt = nil   // importing an entry means it's live
            item.updatedAt = entry.updatedAt ?? entry.dateAdded
        }

        try context.save()
        return (inserted, updated, deleted)
    }

    // MARK: - Codec

    static func decode(_ data: Data) throws -> CollectionArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CollectionArchive.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
