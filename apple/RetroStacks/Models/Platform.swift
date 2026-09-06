import Foundation
import SwiftData

/// A gaming system / platform family, e.g. "Super Nintendo Entertainment System".
///
/// This is reference (catalog) data. Once the real API exists it will be seeded
/// from the server; for now `SampleData` populates it locally.
@Model
final class Platform {
    /// Stable identifier that will map to the server's primary key later.
    @Attribute(.unique) var slug: String

    var name: String
    var shortName: String
    var manufacturer: String

    /// Console hardware generation (2 = Atari 2600 era, 6 = PS2/GameCube era, …).
    var generation: Int

    var releaseYearNA: Int?
    var discontinuedYearNA: Int?

    var summary: String

    /// SF Symbol used as a stand-in until real art is wired up.
    var iconSystemName: String

    /// Stored as raw strings so SwiftData stays happy with a value array.
    private var regionsAvailableRaw: [String]

    @Relationship(deleteRule: .cascade, inverse: \CatalogItem.platform)
    var catalogItems: [CatalogItem] = []

    var regionsAvailable: [Region] {
        get { regionsAvailableRaw.compactMap(Region.init(rawValue:)) }
        set { regionsAvailableRaw = newValue.map(\.rawValue) }
    }

    init(
        slug: String,
        name: String,
        shortName: String,
        manufacturer: String,
        generation: Int,
        releaseYearNA: Int? = nil,
        discontinuedYearNA: Int? = nil,
        summary: String = "",
        iconSystemName: String = "gamecontroller",
        regionsAvailable: [Region] = [.northAmerica]
    ) {
        self.slug = slug
        self.name = name
        self.shortName = shortName
        self.manufacturer = manufacturer
        self.generation = generation
        self.releaseYearNA = releaseYearNA
        self.discontinuedYearNA = discontinuedYearNA
        self.summary = summary
        self.iconSystemName = iconSystemName
        self.regionsAvailableRaw = regionsAvailable.map(\.rawValue)
    }
}

extension Platform {
    var consoles: [CatalogItem] { catalogItems.filter { $0.kind == .console } }
    var games: [CatalogItem] { catalogItems.filter { $0.kind == .game } }
    var accessories: [CatalogItem] { catalogItems.filter { $0.kind == .accessory } }

    func items(of kind: ItemKind) -> [CatalogItem] {
        catalogItems.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    }

    var eraLabel: String {
        switch generation {
        case ...2: "2nd Gen"
        case 3: "3rd Gen (8-bit)"
        case 4: "4th Gen (16-bit)"
        case 5: "5th Gen (32/64-bit)"
        case 6: "6th Gen"
        default: "\(generation)th Gen"
        }
    }
}
