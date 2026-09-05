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

    /// Asset-catalog image name if art is later added; nil falls back to a symbol.
    var imageName: String?

    // Rough US market reference prices (mock values for now).
    var estimatedValueLoose: Decimal?
    var estimatedValueComplete: Decimal?
    var estimatedValueSealed: Decimal?

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
        estimatedValueLoose: Decimal? = nil,
        estimatedValueComplete: Decimal? = nil,
        estimatedValueSealed: Decimal? = nil
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
        self.estimatedValueLoose = estimatedValueLoose
        self.estimatedValueComplete = estimatedValueComplete
        self.estimatedValueSealed = estimatedValueSealed
    }
}

extension CatalogItem {
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
        case .sealed, .graded: estimatedValueSealed ?? estimatedValueComplete
        case .completeInBox, .boxedNoManual: estimatedValueComplete ?? estimatedValueLoose
        case .loose: estimatedValueLoose
        case .none: headlineValue
        }
    }
}
