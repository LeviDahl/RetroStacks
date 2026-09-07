import Foundation
import SwiftData

/// The user's personal record for a `CatalogItem` — ownership, condition, money,
/// and notes. This is the data the tracker is really about.
@Model
final class CollectionItem {
    /// Stable id that survives export → import (and, later, device → device).
    /// `persistentModelID` can't do that job. Optional so adding it to an
    /// existing store migrates cleanly; `SampleData.seedIfNeeded` back-fills any
    /// `nil`s on launch, and `resolvedExportID` never returns nil.
    var exportID: UUID?

    var catalogItem: CatalogItem?

    private var statusRaw: String
    private var conditionRaw: String?
    private var completenessRaw: String?
    private var acquisitionSourceRaw: String?
    private var gradingCompanyRaw: String
    private var playStatusRaw: String?

    // Completeness checklist — what physically came with it.
    var hasBox: Bool
    var hasManual: Bool
    var hasInserts: Bool
    var hasOriginalPackaging: Bool

    var gradeScore: Double?

    var pricePaid: Decimal?
    var dateAcquired: Date?
    var estimatedValueOverride: Decimal?

    var storageLocation: String?
    var notes: String

    /// Raw image bytes. No picker is wired up yet; kept here so the detail UI and
    /// future photo support have a home. Switch to `.externalStorage` per-photo if
    /// this grows.
    var photoData: [Data]

    var dateAdded: Date

    var status: CollectionStatus {
        get { CollectionStatus(rawValue: statusRaw) ?? .owned }
        set { statusRaw = newValue.rawValue }
    }

    var condition: ConditionGrade? {
        get { conditionRaw.flatMap(ConditionGrade.init(rawValue:)) }
        set { conditionRaw = newValue?.rawValue }
    }

    var completeness: Completeness? {
        get { completenessRaw.flatMap(Completeness.init(rawValue:)) }
        set { completenessRaw = newValue?.rawValue }
    }

    var acquisitionSource: AcquisitionSource? {
        get { acquisitionSourceRaw.flatMap(AcquisitionSource.init(rawValue:)) }
        set { acquisitionSourceRaw = newValue?.rawValue }
    }

    var gradingCompany: GradingCompany {
        get { GradingCompany(rawValue: gradingCompanyRaw) ?? .none }
        set { gradingCompanyRaw = newValue.rawValue }
    }

    var playStatus: PlayStatus? {
        get { playStatusRaw.flatMap(PlayStatus.init(rawValue:)) }
        set { playStatusRaw = newValue?.rawValue }
    }

    init(
        catalogItem: CatalogItem? = nil,
        status: CollectionStatus = .owned,
        condition: ConditionGrade? = nil,
        completeness: Completeness? = nil,
        hasBox: Bool = false,
        hasManual: Bool = false,
        hasInserts: Bool = false,
        hasOriginalPackaging: Bool = false,
        gradingCompany: GradingCompany = .none,
        gradeScore: Double? = nil,
        pricePaid: Decimal? = nil,
        dateAcquired: Date? = nil,
        acquisitionSource: AcquisitionSource? = nil,
        estimatedValueOverride: Decimal? = nil,
        storageLocation: String? = nil,
        notes: String = "",
        photoData: [Data] = [],
        playStatus: PlayStatus? = nil,
        dateAdded: Date = .now,
        exportID: UUID? = nil
    ) {
        self.exportID = exportID ?? UUID()
        self.catalogItem = catalogItem
        self.statusRaw = status.rawValue
        self.conditionRaw = condition?.rawValue
        self.completenessRaw = completeness?.rawValue
        self.hasBox = hasBox
        self.hasManual = hasManual
        self.hasInserts = hasInserts
        self.hasOriginalPackaging = hasOriginalPackaging
        self.gradingCompanyRaw = gradingCompany.rawValue
        self.gradeScore = gradeScore
        self.pricePaid = pricePaid
        self.dateAcquired = dateAcquired
        self.acquisitionSourceRaw = acquisitionSource?.rawValue
        self.estimatedValueOverride = estimatedValueOverride
        self.storageLocation = storageLocation
        self.notes = notes
        self.photoData = photoData
        self.playStatusRaw = playStatus?.rawValue
        self.dateAdded = dateAdded
    }
}

extension CollectionItem {
    /// `exportID`, assigning one if this row predates the field.
    var resolvedExportID: UUID {
        if let exportID { return exportID }
        let id = UUID()
        exportID = id
        return id
    }

    var title: String { catalogItem?.displayTitle ?? "Unknown Item" }
    var kind: ItemKind { catalogItem?.kind ?? .game }
    var platformShortName: String { catalogItem?.platformShortName ?? "—" }

    /// Manual override wins, otherwise fall back to catalog reference pricing.
    var estimatedValue: Decimal? {
        estimatedValueOverride ?? catalogItem?.referenceValue(for: completeness)
    }

    /// Positive = up since purchase.
    var valueDelta: Decimal? {
        guard let estimatedValue, let pricePaid else { return nil }
        return estimatedValue - pricePaid
    }

    var completenessChecklistScore: Double {
        let flags = [hasBox, hasManual, hasInserts, hasOriginalPackaging]
        return Double(flags.filter { $0 }.count) / Double(flags.count)
    }
}
