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
    /// The one source of truth for "what a normal browsing view of this
    /// platform actually shows." Raw `catalogItems` includes locally hidden
    /// entries (`CatalogItem.isHidden`), which covers both a personal "not
    /// interested" hide *and* an admin's catalog-wide exclude (represented
    /// the same way locally — see `AdminCatalogCurationService`; no
    /// separate flag). Found live 2026-09-18, twice: excluding ~500 NES
    /// bootlegs moved the filtered browse list, but not `AboutSystemCard`'s
    /// "Catalog" count (fixed by routing it through here) — and *separately*
    /// not Dashboard's platform breakdown, because `.games` below filtered
    /// raw `catalogItems` directly instead of going through this. Every
    /// kind-scoped accessor is now defined *in terms of* this one method
    /// specifically so a third spot can't reappear the same way: there's
    /// nowhere left to filter raw `catalogItems` by kind except here.
    ///
    /// `includeHidden` defaults to matching the same `system.showHidden`
    /// toggle `SystemGamesList` reads, so a count shown before you ever open
    /// that screen still agrees with what it would show once you do.
    ///
    /// Sync/admin-curation code (`CatalogSyncService.reconcile`,
    /// `AdminCatalogCurationService`'s callers) reads raw `catalogItems`
    /// directly on purpose, never this — that logic needs to see hidden
    /// items to re-evaluate them, not just browse what's currently visible.
    func visibleCatalogItems(includeHidden: Bool = UserDefaults.standard.bool(forKey: "system.showHidden")) -> [CatalogItem] {
        includeHidden ? catalogItems : catalogItems.filter { !$0.isHidden }
    }

    var consoles: [CatalogItem] { visibleCatalogItems().filter { $0.kind == .console } }
    var games: [CatalogItem] { visibleCatalogItems().filter { $0.kind == .game } }
    var accessories: [CatalogItem] { visibleCatalogItems().filter { $0.kind == .accessory } }

    func items(of kind: ItemKind) -> [CatalogItem] {
        visibleCatalogItems().filter { $0.kind == kind }.sorted { $0.name < $1.name }
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
