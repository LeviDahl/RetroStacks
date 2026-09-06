import Foundation
import SwiftData

/// A single reference entry: a specific console model, game release, or accessory.
///
/// Catalog data is shared/global (eventually server-owned). The user's personal
/// ownership lives on `CollectionItem`, which points back here.
@Model
final class CatalogItem {
    @Attribute(.unique) var slug: String

    private var kindRaw: String
    var name: String

    /// Distinguishing sub-label: "Model 2", "Player's Choice", "Heavy Sixer", …
    var variant: String?

    var releaseYearNA: Int?

    /// Manufacturer for hardware, publisher for games.
    var manufacturerOrPublisher: String?
    /// Games only.
    var developer: String?
    var genre: String?

    var upc: String?
    var summary: String

    /// Asset-catalog image name if art is later bundled; takes priority over `imageURLString`.
    var imageName: String?

    /// Remote hardware/box photo. Currently a Wikimedia Commons `Special:FilePath`
    /// URL (stable redirect endpoint). Replace with our own CDN later — see the
    /// image-hosting item in `api/README.md`.
    var imageURLString: String?
    /// Attribution shown wherever the image appears, e.g. "Evan-Amos / Wikimedia Commons".
    var imageCredit: String?
    /// e.g. "Public domain", "CC BY-SA 3.0".
    var imageLicense: String?

    /// Cached market values per condition — the last resolved `PriceGuide`,
    /// flattened onto the model so lists / stats / offline use stay synchronous.
    /// Written by `PricingService.apply(_:to:)`; seeded by `SampleData`.
    var estimatedValueLoose: Decimal?
    var estimatedValueComplete: Decimal?
    var estimatedValueSealed: Decimal?
    var estimatedValueGraded: Decimal?

    /// Yearly units sold, per the pricing source (PriceCharting `sales-volume`).
    var salesVolumeYearly: Int?
    /// `PricingProviderID.rawValue` of whichever source produced the cached values.
    var priceGuideProviderID: String?
    var priceGuideUpdatedAt: Date?

    var platform: Platform?

    @Relationship(deleteRule: .cascade, inverse: \CollectionItem.catalogItem)
    var collectionEntries: [CollectionItem] = []

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .game }
        set { kindRaw = newValue.rawValue }
    }

    init(
        slug: String,
        kind: ItemKind,
        name: String,
        variant: String? = nil,
        releaseYearNA: Int? = nil,
        manufacturerOrPublisher: String? = nil,
        developer: String? = nil,
        genre: String? = nil,
        upc: String? = nil,
        summary: String = "",
        imageName: String? = nil,
        imageURLString: String? = nil,
        imageCredit: String? = nil,
        imageLicense: String? = nil,
        estimatedValueLoose: Decimal? = nil,
        estimatedValueComplete: Decimal? = nil,
        estimatedValueSealed: Decimal? = nil,
        estimatedValueGraded: Decimal? = nil,
        salesVolumeYearly: Int? = nil,
        priceGuideProviderID: String? = nil,
        priceGuideUpdatedAt: Date? = nil
    ) {
        self.slug = slug
        self.kindRaw = kind.rawValue
        self.name = name
        self.variant = variant
        self.releaseYearNA = releaseYearNA
        self.manufacturerOrPublisher = manufacturerOrPublisher
        self.developer = developer
        self.genre = genre
        self.upc = upc
        self.summary = summary
        self.imageName = imageName
        self.imageURLString = imageURLString
        self.imageCredit = imageCredit
        self.imageLicense = imageLicense
        self.estimatedValueLoose = estimatedValueLoose
        self.estimatedValueComplete = estimatedValueComplete
        self.estimatedValueSealed = estimatedValueSealed
        self.estimatedValueGraded = estimatedValueGraded
        self.salesVolumeYearly = salesVolumeYearly
        self.priceGuideProviderID = priceGuideProviderID
        self.priceGuideUpdatedAt = priceGuideUpdatedAt
    }
}

extension CatalogItem {
    var imageURL: URL? {
        imageURLString.flatMap { URL(string: $0) }
    }

    /// One-line "Photo: … · License" string, or nil when there's no remote image.
    var imageAttribution: String? {
        guard imageURL != nil, let credit = imageCredit else { return nil }
        if let license = imageLicense { return "Photo: \(credit) · \(license)" }
        return "Photo: \(credit)"
    }

    var displayTitle: String {
        guard let variant, !variant.isEmpty else { return name }
        return "\(name) (\(variant))"
    }

    var platformShortName: String { platform?.shortName ?? "—" }

    var isOwned: Bool {
        collectionEntries.contains { $0.status == .owned }
    }

    var isWishlisted: Bool {
        collectionEntries.contains { $0.status == .wishlist }
    }

    /// Best available reference price for quick display (complete > loose > sealed).
    var headlineValue: Decimal? {
        estimatedValueComplete ?? estimatedValueLoose ?? estimatedValueSealed
    }

    func referenceValue(for completeness: Completeness?) -> Decimal? {
        switch completeness {
        case .graded: estimatedValueGraded ?? estimatedValueSealed ?? estimatedValueComplete
        case .sealed: estimatedValueSealed ?? estimatedValueComplete
        case .completeInBox, .boxedNoManual: estimatedValueComplete ?? estimatedValueLoose
        case .loose: estimatedValueLoose
        case .none: headlineValue
        }
    }

    /// Human label for the source of the cached prices, e.g. "PriceCharting".
    var priceGuideSourceName: String? {
        priceGuideProviderID.map { PricingProviderID($0).displayName }
    }
}
