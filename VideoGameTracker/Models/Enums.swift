import Foundation

/// Market region. v1 focuses on `.northAmerica`; the other cases exist so the
/// data model and future API can expand without migration.
enum Region: String, Codable, CaseIterable, Identifiable, Sendable {
    case northAmerica = "NA"
    case europe = "EU"
    case japan = "JP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .northAmerica: "North America"
        case .europe: "Europe"
        case .japan: "Japan"
        }
    }

    var flagSymbol: String {
        switch self {
        case .northAmerica: "🇺🇸"
        case .europe: "🇪🇺"
        case .japan: "🇯🇵"
        }
    }
}

/// The three top-level things this app catalogs.
enum ItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case console
    case game
    case accessory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .console: "Console"
        case .game: "Game"
        case .accessory: "Accessory"
        }
    }

    var pluralName: String {
        switch self {
        case .console: "Consoles"
        case .game: "Games"
        case .accessory: "Accessories"
        }
    }

    var symbol: String {
        switch self {
        case .console: "gamecontroller"
        case .game: "opticaldiscdrive"
        case .accessory: "cable.connector"
        }
    }
}

/// Where an item sits in the user's collection workflow.
enum CollectionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case owned
    case wishlist
    case forSale
    case forTrade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owned: "Owned"
        case .wishlist: "Wishlist"
        case .forSale: "For Sale"
        case .forTrade: "For Trade"
        }
    }

    var symbol: String {
        switch self {
        case .owned: "checkmark.seal.fill"
        case .wishlist: "star"
        case .forSale: "tag"
        case .forTrade: "arrow.left.arrow.right"
        }
    }
}

/// Physical condition grade, roughly aligned with hobby shorthand.
enum ConditionGrade: String, Codable, CaseIterable, Identifiable, Sendable {
    case sealed
    case mint
    case veryGood
    case good
    case fair
    case poor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sealed: "Sealed"
        case .mint: "Mint"
        case .veryGood: "Very Good"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        }
    }

    /// 0...1 quality ratio, handy for sorting and simple bar visuals.
    var qualityRatio: Double {
        switch self {
        case .sealed: 1.0
        case .mint: 0.9
        case .veryGood: 0.75
        case .good: 0.55
        case .fair: 0.35
        case .poor: 0.15
        }
    }
}

/// What is included with the item — the "completeness" axis, independent of wear.
enum Completeness: String, Codable, CaseIterable, Identifiable, Sendable {
    case sealed
    case graded
    case completeInBox
    case boxedNoManual
    case loose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sealed: "Sealed"
        case .graded: "Graded"
        case .completeInBox: "Complete in Box"
        case .boxedNoManual: "Boxed, No Manual"
        case .loose: "Loose"
        }
    }

    var shortName: String {
        switch self {
        case .sealed: "SEALED"
        case .graded: "GRADED"
        case .completeInBox: "CIB"
        case .boxedNoManual: "BOX"
        case .loose: "LOOSE"
        }
    }
}

enum AcquisitionSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case retail
    case onlineMarketplace
    case localSeller
    case gameStore
    case gift
    case trade
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .retail: "Retail"
        case .onlineMarketplace: "Online Marketplace"
        case .localSeller: "Local Seller"
        case .gameStore: "Game Store"
        case .gift: "Gift"
        case .trade: "Trade"
        case .other: "Other"
        }
    }
}

enum GradingCompany: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case wata = "WATA"
    case vga = "VGA"
    case cgc = "CGC"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Not Graded"
        default: rawValue
        }
    }
}

/// Optional play-through tracking for games.
enum PlayStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case notStarted
    case playing
    case completed
    case abandoned
    case backlog

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: "Not Started"
        case .playing: "Playing"
        case .completed: "Completed"
        case .abandoned: "Abandoned"
        case .backlog: "Backlog"
        }
    }

    var symbol: String {
        switch self {
        case .notStarted: "circle"
        case .playing: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .abandoned: "xmark.circle"
        case .backlog: "tray.full"
        }
    }
}
