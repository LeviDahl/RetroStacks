import Foundation
import SwiftData

/// Hand-authored mock catalog + collection data.
///
/// Shape deliberately mirrors what the future REST API is expected to return, so
/// swapping in a network `CatalogRepository` later is mostly a decoding change.
/// All prices are rough US-market placeholders, not live valuations.
enum SampleData {

    // MARK: - Container factories

    /// A fully populated in-memory container for previews and `#Preview` blocks.
    @MainActor
    static func previewContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        seed(into: container.mainContext)
        return container
    }

    /// On first launch, seeds the full mock data set. On later launches (store
    /// already populated) it just re-applies the hot-linked image URLs, so an
    /// install that predates a batch of new art picks it up without a wipe —
    /// the mock data evolves faster than the store reseeds while there's no
    /// server. Safe to call on every launch.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Platform>())) ?? 0
        if count == 0 {
            seed(into: context)
        } else {
            refreshSampleMedia(in: context)
        }
    }

    /// Rewrites `imageURLString` / credit / license on existing catalog rows to
    /// match the current `attach*` tables. Idempotent (skips rows already set to
    /// the same URL).
    @MainActor
    static func refreshSampleMedia(in context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<CatalogItem>()),
              !items.isEmpty else { return }
        attachConsolePhotos(to: items)
        attachGameBoxArt(to: items)
        if context.hasChanges { try? context.save() }
    }

    // MARK: - Seeding

    @MainActor
    static func seed(into context: ModelContext) {
        let platforms = makePlatforms()
        for platform in platforms { context.insert(platform) }

        let catalog = makeCatalog(platforms: platforms)
        for item in catalog { context.insert(item) }

        for entry in makeCollection(catalog: catalog) { context.insert(entry) }

        try? context.save()
    }

    // MARK: - Platforms

    @MainActor
    static func makePlatforms() -> [Platform] {
        [
            Platform(slug: "atari-2600", name: "Atari 2600", shortName: "2600",
                     manufacturer: "Atari", generation: 2, releaseYearNA: 1977,
                     discontinuedYearNA: 1992,
                     summary: "The cartridge-based console that defined the second generation and the 1977–1983 home boom.",
                     iconSystemName: "joystick"),
            Platform(slug: "nes", name: "Nintendo Entertainment System", shortName: "NES",
                     manufacturer: "Nintendo", generation: 3, releaseYearNA: 1985,
                     discontinuedYearNA: 1995,
                     summary: "Revived the US console market after the 1983 crash; the 8-bit baseline for the hobby.",
                     iconSystemName: "gamecontroller"),
            Platform(slug: "snes", name: "Super Nintendo Entertainment System", shortName: "SNES",
                     manufacturer: "Nintendo", generation: 4, releaseYearNA: 1991,
                     discontinuedYearNA: 1999,
                     summary: "16-bit Nintendo. Deep RPG library and some of the most valuable complete-in-box games.",
                     iconSystemName: "gamecontroller"),
            Platform(slug: "genesis", name: "Sega Genesis", shortName: "GEN",
                     manufacturer: "Sega", generation: 4, releaseYearNA: 1989,
                     discontinuedYearNA: 1997,
                     summary: "Sega's 16-bit machine, sold as Mega Drive elsewhere. \"Blast processing\" and Sonic.",
                     iconSystemName: "gamecontroller"),
            Platform(slug: "game-boy", name: "Nintendo Game Boy", shortName: "GB",
                     manufacturer: "Nintendo", generation: 4, releaseYearNA: 1989,
                     discontinuedYearNA: 2003,
                     summary: "The handheld that mattered. Tetris pack-in, monochrome screen, runs for a week on AAs.",
                     iconSystemName: "rectangle.portrait"),
            Platform(slug: "n64", name: "Nintendo 64", shortName: "N64",
                     manufacturer: "Nintendo", generation: 5, releaseYearNA: 1996,
                     discontinuedYearNA: 2002,
                     summary: "Cartridge-based 64-bit console. Analog stick, four controller ports, defined 3D platformers.",
                     iconSystemName: "gamecontroller"),
            Platform(slug: "playstation", name: "Sony PlayStation", shortName: "PS1",
                     manufacturer: "Sony", generation: 5, releaseYearNA: 1995,
                     discontinuedYearNA: 2006,
                     summary: "CD-based, developer-friendly, and the machine that took RPGs and cinematic games mainstream.",
                     iconSystemName: "opticaldiscdrive"),
            Platform(slug: "dreamcast", name: "Sega Dreamcast", shortName: "DC",
                     manufacturer: "Sega", generation: 6, releaseYearNA: 1999,
                     discontinuedYearNA: 2001,
                     summary: "Sega's last console. Online play out of the box, VMU memory cards, a short but beloved life.",
                     iconSystemName: "opticaldiscdrive"),
            Platform(slug: "ps2", name: "Sony PlayStation 2", shortName: "PS2",
                     manufacturer: "Sony", generation: 6, releaseYearNA: 2000,
                     discontinuedYearNA: 2013,
                     summary: "Best-selling console of all time. Played DVDs, huge library, backward compatible with PS1.",
                     iconSystemName: "opticaldiscdrive"),
            Platform(slug: "gamecube", name: "Nintendo GameCube", shortName: "GCN",
                     manufacturer: "Nintendo", generation: 6, releaseYearNA: 2001,
                     discontinuedYearNA: 2007,
                     summary: "Mini-DVD discs, purple lunchbox, the WaveBird wireless controller, and a strong first-party lineup.",
                     iconSystemName: "cube"),
        ]
    }

    // MARK: - Catalog

    @MainActor
    static func makeCatalog(platforms: [Platform]) -> [CatalogItem] {
        var byslug: [String: Platform] = [:]
        for p in platforms { byslug[p.slug] = p }
        var items: [CatalogItem] = []

        func add(_ platformSlug: String, _ item: CatalogItem) {
            item.platform = byslug[platformSlug]
            items.append(item)
        }

        // --- Atari 2600 -----------------------------------------------------
        add("atari-2600", CatalogItem(slug: "2600-heavy-sixer", kind: .console, name: "Atari 2600", variant: "Heavy Sixer",
            releaseYearNA: 1977, manufacturerOrPublisher: "Atari",
            summary: "First-run 1977 unit with six switches on the front face and thicker casing.",
            estimatedValueLoose: 120, estimatedValueComplete: 320, estimatedValueSealed: 1800))
        add("atari-2600", CatalogItem(slug: "2600-4switch", kind: .console, name: "Atari 2600", variant: "4-Switch",
            releaseYearNA: 1980, manufacturerOrPublisher: "Atari",
            summary: "The common woodgrain 4-switch revision most collectors start with.",
            estimatedValueLoose: 45, estimatedValueComplete: 110, estimatedValueSealed: 600))
        add("atari-2600", CatalogItem(slug: "2600-pitfall", kind: .game, name: "Pitfall!",
            releaseYearNA: 1982, manufacturerOrPublisher: "Activision", developer: "Activision", genre: "Platformer",
            summary: "David Crane's jungle runner; one of the best-selling 2600 titles.",
            estimatedValueLoose: 8, estimatedValueComplete: 35, estimatedValueSealed: 400))
        add("atari-2600", CatalogItem(slug: "2600-adventure", kind: .game, name: "Adventure",
            releaseYearNA: 1980, manufacturerOrPublisher: "Atari", developer: "Atari", genre: "Action-Adventure",
            summary: "First action-adventure game and home of gaming's first widely known Easter egg.",
            estimatedValueLoose: 10, estimatedValueComplete: 45, estimatedValueSealed: 650))
        add("atari-2600", CatalogItem(slug: "2600-cx40", kind: .accessory, name: "CX40 Joystick",
            releaseYearNA: 1977, manufacturerOrPublisher: "Atari",
            summary: "The iconic single-button black joystick. Notorious for worn-out contacts.",
            estimatedValueLoose: 15, estimatedValueComplete: 40, estimatedValueSealed: 150))

        // --- NES ----------------------------------------------------------
        add("nes", CatalogItem(slug: "nes-001", kind: .console, name: "NES Control Deck", variant: "NES-001",
            releaseYearNA: 1985, manufacturerOrPublisher: "Nintendo",
            summary: "The original front-loading \"toaster\". Zero Insertion Force connector wears with use.",
            estimatedValueLoose: 70, estimatedValueComplete: 260, estimatedValueSealed: 4200))
        add("nes", CatalogItem(slug: "nes-top-loader", kind: .console, name: "NES", variant: "Top Loader (NES-101)",
            releaseYearNA: 1993, manufacturerOrPublisher: "Nintendo",
            summary: "Late-run redesign with a reliable top-loading slot. No composite out.",
            estimatedValueLoose: 160, estimatedValueComplete: 420, estimatedValueSealed: 3000))
        add("nes", CatalogItem(slug: "nes-smb3", kind: .game, name: "Super Mario Bros. 3",
            releaseYearNA: 1990, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Platformer",
            summary: "Peak 2D Mario for the platform; the movie-hyped 1990 blockbuster.",
            estimatedValueLoose: 12, estimatedValueComplete: 70, estimatedValueSealed: 3800))
        add("nes", CatalogItem(slug: "nes-zelda", kind: .game, name: "The Legend of Zelda",
            releaseYearNA: 1987, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "Gold cartridge, battery-backed saves, open exploration.",
            estimatedValueLoose: 30, estimatedValueComplete: 180, estimatedValueSealed: 9000))
        add("nes", CatalogItem(slug: "nes-metroid", kind: .game, name: "Metroid",
            releaseYearNA: 1987, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "Password-based, atmospheric, and the start of the series.",
            estimatedValueLoose: 22, estimatedValueComplete: 160, estimatedValueSealed: 5500))
        add("nes", CatalogItem(slug: "nes-zapper", kind: .accessory, name: "NES Zapper",
            releaseYearNA: 1985, manufacturerOrPublisher: "Nintendo",
            summary: "Light gun for Duck Hunt and friends. Grey and orange variants exist.",
            estimatedValueLoose: 12, estimatedValueComplete: 35, estimatedValueSealed: 220))
        add("nes", CatalogItem(slug: "nes-advantage", kind: .accessory, name: "NES Advantage",
            releaseYearNA: 1987, manufacturerOrPublisher: "Nintendo",
            summary: "Arcade-style joystick with turbo dials and slow-motion.",
            estimatedValueLoose: 20, estimatedValueComplete: 55, estimatedValueSealed: 300))

        // --- SNES -------------------------------------------------------
        add("snes", CatalogItem(slug: "sns-001", kind: .console, name: "Super Nintendo", variant: "SNS-001",
            releaseYearNA: 1991, manufacturerOrPublisher: "Nintendo",
            summary: "The original curvy US model. Plastic is prone to yellowing.",
            estimatedValueLoose: 90, estimatedValueComplete: 300, estimatedValueSealed: 6000))
        add("snes", CatalogItem(slug: "snes-jr", kind: .console, name: "Super Nintendo", variant: "Jr. (SNS-101)",
            releaseYearNA: 1997, manufacturerOrPublisher: "Nintendo",
            summary: "Compact redesign, no eject lever, no S-Video. Resists yellowing better.",
            estimatedValueLoose: 130, estimatedValueComplete: 380, estimatedValueSealed: 4500))
        add("snes", CatalogItem(slug: "snes-mario-world", kind: .game, name: "Super Mario World",
            releaseYearNA: 1991, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Platformer",
            summary: "Pack-in title; introduced Yoshi.",
            estimatedValueLoose: 15, estimatedValueComplete: 65, estimatedValueSealed: 3000))
        add("snes", CatalogItem(slug: "snes-chrono-trigger", kind: .game, name: "Chrono Trigger",
            releaseYearNA: 1995, manufacturerOrPublisher: "Square", developer: "Square", genre: "RPG",
            summary: "Dream-team JRPG with multiple endings. Big-box, high-demand CIB.",
            estimatedValueLoose: 130, estimatedValueComplete: 450, estimatedValueSealed: 15000))
        add("snes", CatalogItem(slug: "snes-link-past", kind: .game, name: "The Legend of Zelda: A Link to the Past",
            releaseYearNA: 1992, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "Light/dark world design template for decades of Zelda.",
            estimatedValueLoose: 20, estimatedValueComplete: 90, estimatedValueSealed: 4000))
        add("snes", CatalogItem(slug: "snes-super-metroid", kind: .game, name: "Super Metroid",
            releaseYearNA: 1994, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "The genre-namesake. Big-box release.",
            estimatedValueLoose: 45, estimatedValueComplete: 160, estimatedValueSealed: 7000))
        add("snes", CatalogItem(slug: "snes-mouse", kind: .accessory, name: "SNES Mouse",
            releaseYearNA: 1992, manufacturerOrPublisher: "Nintendo",
            summary: "Bundled with Mario Paint; also works with a handful of strategy titles.",
            estimatedValueLoose: 10, estimatedValueComplete: 30, estimatedValueSealed: 120))
        add("snes", CatalogItem(slug: "snes-multitap", kind: .accessory, name: "Super Multitap",
            releaseYearNA: 1992, manufacturerOrPublisher: "Nintendo",
            summary: "Adapter for up to five players; required for Bomberman parties.",
            estimatedValueLoose: 14, estimatedValueComplete: 35, estimatedValueSealed: 110))

        // --- Genesis ---------------------------------------------------
        add("genesis", CatalogItem(slug: "gen-model-1", kind: .console, name: "Genesis", variant: "Model 1 (High Definition Graphics)",
            releaseYearNA: 1989, manufacturerOrPublisher: "Sega",
            summary: "First US revision with the \"HIGH DEFINITION GRAPHICS\" stamp and headphone jack.",
            estimatedValueLoose: 55, estimatedValueComplete: 170, estimatedValueSealed: 2200))
        add("genesis", CatalogItem(slug: "gen-model-2", kind: .console, name: "Genesis", variant: "Model 2",
            releaseYearNA: 1993, manufacturerOrPublisher: "Sega",
            summary: "Smaller, cheaper redesign. The most common Genesis today.",
            estimatedValueLoose: 40, estimatedValueComplete: 120, estimatedValueSealed: 900))
        add("genesis", CatalogItem(slug: "gen-sonic-2", kind: .game, name: "Sonic the Hedgehog 2",
            releaseYearNA: 1992, manufacturerOrPublisher: "Sega", developer: "Sega Technical Institute", genre: "Platformer",
            summary: "Added Tails and the spin dash. Extremely common — a great starter cart.",
            estimatedValueLoose: 6, estimatedValueComplete: 20, estimatedValueSealed: 500))
        add("genesis", CatalogItem(slug: "gen-streets-2", kind: .game, name: "Streets of Rage 2",
            releaseYearNA: 1992, manufacturerOrPublisher: "Sega", developer: "Sega", genre: "Beat 'em up",
            summary: "Benchmark 16-bit brawler with a landmark Yuzo Koshiro soundtrack.",
            estimatedValueLoose: 25, estimatedValueComplete: 70, estimatedValueSealed: 1400))
        add("genesis", CatalogItem(slug: "gen-psiv", kind: .game, name: "Phantasy Star IV",
            releaseYearNA: 1995, manufacturerOrPublisher: "Sega", developer: "Sega", genre: "RPG",
            summary: "Late, low-print JRPG. One of the platform's priciest CIB games.",
            estimatedValueLoose: 120, estimatedValueComplete: 350, estimatedValueSealed: 6000))
        add("genesis", CatalogItem(slug: "gen-6button", kind: .accessory, name: "6-Button Arcade Pad",
            releaseYearNA: 1993, manufacturerOrPublisher: "Sega",
            summary: "Six face buttons and a mode switch; near-essential for fighting games.",
            estimatedValueLoose: 12, estimatedValueComplete: 30, estimatedValueSealed: 90))
        add("genesis", CatalogItem(slug: "gen-32x", kind: .accessory, name: "Sega 32X",
            releaseYearNA: 1994, manufacturerOrPublisher: "Sega",
            summary: "Mushroom-shaped 32-bit add-on with a short, troubled life.",
            estimatedValueLoose: 60, estimatedValueComplete: 150, estimatedValueSealed: 1200))

        // --- Game Boy -------------------------------------------------
        add("game-boy", CatalogItem(slug: "gb-dmg-01", kind: .console, name: "Game Boy", variant: "DMG-01",
            releaseYearNA: 1989, manufacturerOrPublisher: "Nintendo",
            summary: "The original grey brick. Screens commonly show missing-line rot today.",
            estimatedValueLoose: 60, estimatedValueComplete: 220, estimatedValueSealed: 3500))
        add("game-boy", CatalogItem(slug: "gb-pocket", kind: .console, name: "Game Boy Pocket", variant: "MGB-001",
            releaseYearNA: 1996, manufacturerOrPublisher: "Nintendo",
            summary: "Smaller, two AAA batteries, sharper true-black screen.",
            estimatedValueLoose: 55, estimatedValueComplete: 160, estimatedValueSealed: 1500))
        add("game-boy", CatalogItem(slug: "gb-tetris", kind: .game, name: "Tetris",
            releaseYearNA: 1989, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Puzzle",
            summary: "The pack-in that sold the hardware. Ubiquitous and cheap loose.",
            estimatedValueLoose: 8, estimatedValueComplete: 30, estimatedValueSealed: 900))
        add("game-boy", CatalogItem(slug: "gb-pokemon-red", kind: .game, name: "Pokémon Red Version",
            releaseYearNA: 1998, manufacturerOrPublisher: "Nintendo", developer: "Game Freak", genre: "RPG",
            summary: "Launched a franchise. Dead save battery is the norm; check before buying CIB.",
            estimatedValueLoose: 35, estimatedValueComplete: 150, estimatedValueSealed: 5000))
        add("game-boy", CatalogItem(slug: "gb-links-awakening", kind: .game, name: "The Legend of Zelda: Link's Awakening",
            releaseYearNA: 1993, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "Full Zelda on a handheld; a technical showcase for the DMG.",
            estimatedValueLoose: 18, estimatedValueComplete: 60, estimatedValueSealed: 1600))
        add("game-boy", CatalogItem(slug: "gb-camera", kind: .accessory, name: "Game Boy Camera",
            releaseYearNA: 1998, manufacturerOrPublisher: "Nintendo",
            summary: "Rotating-lens cartridge camera. Yellow is common; other colors carry a premium.",
            estimatedValueLoose: 25, estimatedValueComplete: 60, estimatedValueSealed: 250))

        // --- N64 -----------------------------------------------------
        add("n64", CatalogItem(slug: "nus-001", kind: .console, name: "Nintendo 64", variant: "NUS-001 (Charcoal)",
            releaseYearNA: 1996, manufacturerOrPublisher: "Nintendo",
            summary: "Standard charcoal-grey console. Jumper pak must be seated or it won't boot.",
            estimatedValueLoose: 55, estimatedValueComplete: 200, estimatedValueSealed: 2600))
        add("n64", CatalogItem(slug: "n64-mario64", kind: .game, name: "Super Mario 64",
            releaseYearNA: 1996, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Platformer",
            summary: "Launch title and the 3D-platformer blueprint.",
            estimatedValueLoose: 20, estimatedValueComplete: 75, estimatedValueSealed: 5500))
        add("n64", CatalogItem(slug: "n64-oot", kind: .game, name: "The Legend of Zelda: Ocarina of Time",
            releaseYearNA: 1998, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "Grey vs. gold cart and \"Collector's Edition\" box variants matter to collectors.",
            estimatedValueLoose: 22, estimatedValueComplete: 90, estimatedValueSealed: 4300))
        add("n64", CatalogItem(slug: "n64-goldeneye", kind: .game, name: "GoldenEye 007",
            releaseYearNA: 1997, manufacturerOrPublisher: "Nintendo", developer: "Rare", genre: "FPS",
            summary: "The console shooter that defined split-screen multiplayer.",
            estimatedValueLoose: 15, estimatedValueComplete: 60, estimatedValueSealed: 3000))
        add("n64", CatalogItem(slug: "n64-mariokart64", kind: .game, name: "Mario Kart 64",
            releaseYearNA: 1997, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Racing",
            summary: "Four-player kart racing; a permanent party fixture.",
            estimatedValueLoose: 18, estimatedValueComplete: 55, estimatedValueSealed: 2400))
        add("n64", CatalogItem(slug: "n64-expansion-pak", kind: .accessory, name: "Expansion Pak",
            releaseYearNA: 1999, manufacturerOrPublisher: "Nintendo",
            summary: "Doubles system RAM to 8 MB. Required for Donkey Kong 64 and Majora's Mask.",
            estimatedValueLoose: 25, estimatedValueComplete: 70, estimatedValueSealed: 260))
        add("n64", CatalogItem(slug: "n64-rumble-pak", kind: .accessory, name: "Rumble Pak",
            releaseYearNA: 1997, manufacturerOrPublisher: "Nintendo",
            summary: "Controller-pak-slot force feedback; runs on two AAA batteries.",
            estimatedValueLoose: 10, estimatedValueComplete: 28, estimatedValueSealed: 120))

        // --- PlayStation -------------------------------------------
        add("playstation", CatalogItem(slug: "scph-1001", kind: .console, name: "PlayStation", variant: "SCPH-1001",
            releaseYearNA: 1995, manufacturerOrPublisher: "Sony",
            summary: "Launch model with RCA out and the sought-after early sound chip.",
            estimatedValueLoose: 60, estimatedValueComplete: 190, estimatedValueSealed: 2800))
        add("playstation", CatalogItem(slug: "ps-one", kind: .console, name: "PS one", variant: "SCPH-101",
            releaseYearNA: 2000, manufacturerOrPublisher: "Sony",
            summary: "Compact redesign released alongside the PS2. Optional clip-on LCD screen.",
            estimatedValueLoose: 45, estimatedValueComplete: 130, estimatedValueSealed: 1000))
        add("playstation", CatalogItem(slug: "ps1-ff7", kind: .game, name: "Final Fantasy VII",
            releaseYearNA: 1997, manufacturerOrPublisher: "Sony Computer Entertainment", developer: "Square", genre: "RPG",
            summary: "Three discs, black-label and Greatest Hits printings. The Western JRPG breakout.",
            estimatedValueLoose: 20, estimatedValueComplete: 55, estimatedValueSealed: 1800))
        add("playstation", CatalogItem(slug: "ps1-mgs", kind: .game, name: "Metal Gear Solid",
            releaseYearNA: 1998, manufacturerOrPublisher: "Konami", developer: "Konami", genre: "Stealth",
            summary: "Two discs; the VR Missions add-on is a separate release.",
            estimatedValueLoose: 22, estimatedValueComplete: 60, estimatedValueSealed: 2000))
        add("playstation", CatalogItem(slug: "ps1-sotn", kind: .game, name: "Castlevania: Symphony of the Night",
            releaseYearNA: 1997, manufacturerOrPublisher: "Konami", developer: "Konami", genre: "Action-Adventure",
            summary: "The \"Metroidvania\" cornerstone. Long-box and jewel-case printings vary wildly in price.",
            estimatedValueLoose: 60, estimatedValueComplete: 180, estimatedValueSealed: 6000))
        add("playstation", CatalogItem(slug: "ps1-dualshock", kind: .accessory, name: "DualShock Controller", variant: "SCPH-1200",
            releaseYearNA: 1998, manufacturerOrPublisher: "Sony",
            summary: "Added dual analog sticks and vibration; the template for every pad since.",
            estimatedValueLoose: 12, estimatedValueComplete: 35, estimatedValueSealed: 150))
        add("playstation", CatalogItem(slug: "ps1-memcard", kind: .accessory, name: "Memory Card", variant: "1 MB",
            releaseYearNA: 1995, manufacturerOrPublisher: "Sony",
            summary: "15 save blocks. Third-party cards are hit-or-miss; first-party holds value.",
            estimatedValueLoose: 8, estimatedValueComplete: 20, estimatedValueSealed: 70))

        // --- Dreamcast --------------------------------------------
        add("dreamcast", CatalogItem(slug: "hkt-3020", kind: .console, name: "Dreamcast", variant: "HKT-3020",
            releaseYearNA: 1999, manufacturerOrPublisher: "Sega",
            summary: "Standard US console. Launch \"9/9/99\" bundles command a premium.",
            estimatedValueLoose: 70, estimatedValueComplete: 190, estimatedValueSealed: 2400))
        add("dreamcast", CatalogItem(slug: "dc-sonic-adventure", kind: .game, name: "Sonic Adventure",
            releaseYearNA: 1999, manufacturerOrPublisher: "Sega", developer: "Sonic Team", genre: "Platformer",
            summary: "Launch title; \"Not for Resale\" and standard versions exist.",
            estimatedValueLoose: 10, estimatedValueComplete: 25, estimatedValueSealed: 400))
        add("dreamcast", CatalogItem(slug: "dc-shenmue", kind: .game, name: "Shenmue",
            releaseYearNA: 2000, manufacturerOrPublisher: "Sega", developer: "Sega AM2", genre: "Action-Adventure",
            summary: "Four discs including a passport disc. Famously expensive to make.",
            estimatedValueLoose: 30, estimatedValueComplete: 70, estimatedValueSealed: 900))
        add("dreamcast", CatalogItem(slug: "dc-jet-grind-radio", kind: .game, name: "Jet Grind Radio",
            releaseYearNA: 2000, manufacturerOrPublisher: "Sega", developer: "Smilebit", genre: "Action",
            summary: "Cel-shaded landmark, retitled from Jet Set Radio for the US.",
            estimatedValueLoose: 35, estimatedValueComplete: 85, estimatedValueSealed: 1200))
        add("dreamcast", CatalogItem(slug: "dc-vmu", kind: .accessory, name: "Visual Memory Unit (VMU)",
            releaseYearNA: 1999, manufacturerOrPublisher: "Sega",
            summary: "Memory card with a screen and buttons; some games run mini-games on it.",
            estimatedValueLoose: 15, estimatedValueComplete: 35, estimatedValueSealed: 140))

        // --- PS2 -------------------------------------------------
        add("ps2", CatalogItem(slug: "scph-30001", kind: .console, name: "PlayStation 2", variant: "Fat (SCPH-30001)",
            releaseYearNA: 2000, manufacturerOrPublisher: "Sony",
            summary: "Original vertical-capable unit. Disc Read Errors are the classic failure mode.",
            estimatedValueLoose: 55, estimatedValueComplete: 150, estimatedValueSealed: 1600))
        add("ps2", CatalogItem(slug: "ps2-slim", kind: .console, name: "PlayStation 2", variant: "Slim (SCPH-70012)",
            releaseYearNA: 2004, manufacturerOrPublisher: "Sony",
            summary: "Dramatically smaller, external power brick on early slims.",
            estimatedValueLoose: 50, estimatedValueComplete: 130, estimatedValueSealed: 1100))
        add("ps2", CatalogItem(slug: "ps2-sotc", kind: .game, name: "Shadow of the Colossus",
            releaseYearNA: 2005, manufacturerOrPublisher: "Sony Computer Entertainment", developer: "Team Ico", genre: "Action-Adventure",
            summary: "Sixteen boss fights, no filler. A frequent \"games as art\" reference.",
            estimatedValueLoose: 12, estimatedValueComplete: 30, estimatedValueSealed: 700))
        add("ps2", CatalogItem(slug: "ps2-gow", kind: .game, name: "God of War",
            releaseYearNA: 2005, manufacturerOrPublisher: "Sony Computer Entertainment", developer: "Santa Monica Studio", genre: "Action",
            summary: "Two-disc black-label and Greatest Hits printings.",
            estimatedValueLoose: 8, estimatedValueComplete: 22, estimatedValueSealed: 450))
        add("ps2", CatalogItem(slug: "ps2-gta-sa", kind: .game, name: "Grand Theft Auto: San Andreas",
            releaseYearNA: 2004, manufacturerOrPublisher: "Rockstar Games", developer: "Rockstar North", genre: "Action-Adventure",
            summary: "First-print discs contain the \"Hot Coffee\" content; later runs are re-rated.",
            estimatedValueLoose: 10, estimatedValueComplete: 28, estimatedValueSealed: 900))
        add("ps2", CatalogItem(slug: "ps2-dualshock2", kind: .accessory, name: "DualShock 2",
            releaseYearNA: 2000, manufacturerOrPublisher: "Sony",
            summary: "Pressure-sensitive face buttons; otherwise DualShock-compatible.",
            estimatedValueLoose: 10, estimatedValueComplete: 25, estimatedValueSealed: 90))
        add("ps2", CatalogItem(slug: "ps2-8mb-card", kind: .accessory, name: "Memory Card", variant: "8 MB",
            releaseYearNA: 2000, manufacturerOrPublisher: "Sony",
            summary: "MagicGate-encrypted. Third-party high-capacity cards were common but risky.",
            estimatedValueLoose: 7, estimatedValueComplete: 18, estimatedValueSealed: 60))

        // --- GameCube -------------------------------------------
        add("gamecube", CatalogItem(slug: "dol-001", kind: .console, name: "GameCube", variant: "DOL-001 (Indigo)",
            releaseYearNA: 2001, manufacturerOrPublisher: "Nintendo",
            summary: "Full-size unit with the digital AV port used by component cables.",
            estimatedValueLoose: 65, estimatedValueComplete: 190, estimatedValueSealed: 2200))
        add("gamecube", CatalogItem(slug: "gcn-smash-melee", kind: .game, name: "Super Smash Bros. Melee",
            releaseYearNA: 2001, manufacturerOrPublisher: "Nintendo", developer: "HAL Laboratory", genre: "Fighting",
            summary: "The platform's best-seller; still tournament-active.",
            estimatedValueLoose: 25, estimatedValueComplete: 60, estimatedValueSealed: 1400))
        add("gamecube", CatalogItem(slug: "gcn-metroid-prime", kind: .game, name: "Metroid Prime",
            releaseYearNA: 2002, manufacturerOrPublisher: "Nintendo", developer: "Retro Studios", genre: "Action-Adventure",
            summary: "First-person Metroid. Player's Choice reprint is common and cheaper.",
            estimatedValueLoose: 15, estimatedValueComplete: 40, estimatedValueSealed: 900))
        add("gamecube", CatalogItem(slug: "gcn-wind-waker", kind: .game, name: "The Legend of Zelda: The Wind Waker",
            releaseYearNA: 2003, manufacturerOrPublisher: "Nintendo", developer: "Nintendo", genre: "Action-Adventure",
            summary: "Launch pre-orders included a bonus disc with Ocarina of Time + Master Quest.",
            estimatedValueLoose: 18, estimatedValueComplete: 50, estimatedValueSealed: 1100))
        add("gamecube", CatalogItem(slug: "gcn-re4", kind: .game, name: "Resident Evil 4",
            releaseYearNA: 2005, manufacturerOrPublisher: "Capcom", developer: "Capcom Production Studio 4", genre: "Survival Horror",
            summary: "Two discs; the debut of the over-the-shoulder action-horror template.",
            estimatedValueLoose: 16, estimatedValueComplete: 45, estimatedValueSealed: 1000))
        add("gamecube", CatalogItem(slug: "gcn-wavebird", kind: .accessory, name: "WaveBird Wireless Controller",
            releaseYearNA: 2002, manufacturerOrPublisher: "Nintendo",
            summary: "RF wireless, no rumble. The receiver dongle is frequently missing.",
            estimatedValueLoose: 35, estimatedValueComplete: 90, estimatedValueSealed: 400))
        add("gamecube", CatalogItem(slug: "gcn-gb-player", kind: .accessory, name: "Game Boy Player",
            releaseYearNA: 2003, manufacturerOrPublisher: "Nintendo",
            summary: "Bottom-mount adapter that plays GB/GBC/GBA carts. Needs its boot disc.",
            estimatedValueLoose: 40, estimatedValueComplete: 100, estimatedValueSealed: 500))

        attachConsolePhotos(to: items)
        attachGameBoxArt(to: items)
        attachSamplePriceMeta(to: items)
        return items
    }

    /// Front box art for the sample games, hot-linked from the **Libretro
    /// thumbnails** CDN (`thumbnails.libretro.com/<system>/Named_Boxarts/<No-Intro
    /// name>.png`) — the same "URLs only, no backend" approach as the console
    /// photos. Titles below were each verified to return an image. A miss would
    /// just fall back to the placeholder (`ItemThumbnail` handles `.failure`).
    /// This is publisher artwork; our own image layer is the long-term plan
    /// (see `api/README.md`).
    @MainActor
    private static func attachGameBoxArt(to items: [CatalogItem]) {
        var bySlug: [String: CatalogItem] = [:]
        for item in items { bySlug[item.slug] = item }

        func set(_ slug: String, _ system: String, _ title: String) {
            guard let item = bySlug[slug] else { return }
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = "thumbnails.libretro.com"
            comps.path = "/\(system)/Named_Boxarts/\(title).png"
            guard let url = comps.url?.absoluteString, item.imageURLString != url else { return }
            item.imageURLString = url
            item.imageCredit = "Box art via Libretro thumbnails"
            item.imageLicense = "Publisher artwork"
        }

        let a2600 = "Atari - 2600"
        let nes = "Nintendo - Nintendo Entertainment System"
        let snes = "Nintendo - Super Nintendo Entertainment System"
        let gen = "Sega - Mega Drive - Genesis"
        let gb = "Nintendo - Game Boy"
        let n64 = "Nintendo - Nintendo 64"
        let ps1 = "Sony - PlayStation"
        let dc = "Sega - Dreamcast"
        let ps2 = "Sony - PlayStation 2"
        let gcn = "Nintendo - GameCube"

        set("2600-pitfall", a2600, "Pitfall! - Pitfall Harry's Jungle Adventure (USA)")
        set("2600-adventure", a2600, "Adventure (USA)")
        set("nes-smb3", nes, "Super Mario Bros. 3 (USA)")
        set("nes-zelda", nes, "Legend of Zelda, The (USA)")
        set("nes-metroid", nes, "Metroid (USA)")
        set("snes-mario-world", snes, "Super Mario World (USA)")
        set("snes-chrono-trigger", snes, "Chrono Trigger (USA)")
        set("snes-link-past", snes, "Legend of Zelda, The - A Link to the Past (USA)")
        set("snes-super-metroid", snes, "Super Metroid (Japan, USA) (En,Ja)")
        set("gen-sonic-2", gen, "Sonic The Hedgehog 2 (World)")
        set("gen-streets-2", gen, "Streets of Rage 2 (USA)")
        set("gen-psiv", gen, "Phantasy Star IV (USA)")
        set("gb-tetris", gb, "Tetris (World) (Rev 1)")
        set("gb-pokemon-red", gb, "Pokemon - Red Version (USA, Europe) (SGB Enhanced)")
        set("gb-links-awakening", gb, "Legend of Zelda, The - Link's Awakening (USA, Europe)")
        set("n64-mario64", n64, "Super Mario 64 (USA)")
        set("n64-oot", n64, "Legend of Zelda, The - Ocarina of Time (USA)")
        set("n64-goldeneye", n64, "GoldenEye 007 (USA)")
        set("n64-mariokart64", n64, "Mario Kart 64 (USA)")
        set("ps1-ff7", ps1, "Final Fantasy VII (USA) (Disc 1)")
        set("ps1-mgs", ps1, "Metal Gear Solid (USA) (Disc 1)")
        set("ps1-sotn", ps1, "Castlevania - Symphony of the Night (USA)")
        set("dc-sonic-adventure", dc, "Sonic Adventure (USA)")
        set("dc-shenmue", dc, "Shenmue (USA) (Disc 1)")
        set("dc-jet-grind-radio", dc, "Jet Grind Radio (USA)")
        set("ps2-sotc", ps2, "Shadow of the Colossus (USA)")
        set("ps2-gow", ps2, "God of War (USA)")
        set("ps2-gta-sa", ps2, "Grand Theft Auto - San Andreas (USA) (v3.00)")
        set("gcn-smash-melee", gcn, "Super Smash Bros. Melee (USA)")
        set("gcn-metroid-prime", gcn, "Metroid Prime (USA)")
        set("gcn-wind-waker", gcn, "Legend of Zelda, The - The Wind Waker (USA)")
        set("gcn-re4", gcn, "Resident Evil 4 (USA) (Disc 1)")
    }

    /// Tags every seeded item as coming from the built-in guide, and adds a
    /// graded value + yearly sales volume to a few marquee entries so the
    /// "Market Value" card has something to show before a live provider is wired.
    @MainActor
    private static func attachSamplePriceMeta(to items: [CatalogItem]) {
        let asOf = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
        var bySlug: [String: CatalogItem] = [:]
        for item in items {
            item.priceGuideProviderID = PricingProviderID.sampleGuide.rawValue
            item.priceGuideUpdatedAt = asOf
            bySlug[item.slug] = item
        }

        func extra(_ slug: String, graded: Decimal? = nil, salesPerYear: Int? = nil) {
            guard let item = bySlug[slug] else { return }
            if let graded { item.estimatedValueGraded = graded }
            if let salesPerYear { item.salesVolumeYearly = salesPerYear }
        }

        extra("snes-chrono-trigger", graded: 22000, salesPerYear: 140)
        extra("snes-super-metroid", graded: 12000, salesPerYear: 260)
        extra("nes-zelda", graded: 26000, salesPerYear: 90)
        extra("nes-smb3", graded: 9000, salesPerYear: 410)
        extra("n64-oot", graded: 6800, salesPerYear: 520)
        extra("gb-pokemon-red", graded: 8500, salesPerYear: 900)
        extra("ps1-ff7", graded: 3200, salesPerYear: 640)
        extra("gen-psiv", graded: 9000, salesPerYear: 45)
    }

    /// Real hardware photos for each platform's primary console model, pulled from
    /// Wikimedia Commons via the stable `Special:FilePath` redirect endpoint.
    /// Nearly all are Evan Amos's public-domain studio shots (clean white
    /// background); the Dreamcast shot is CC BY-SA 3.0, hence the per-item license.
    /// Variants and games/accessories still fall back to the placeholder — see the
    /// image-hosting backlog item in `api/README.md`.
    @MainActor
    private static func attachConsolePhotos(to items: [CatalogItem]) {
        var bySlug: [String: CatalogItem] = [:]
        for item in items { bySlug[item.slug] = item }

        func set(_ slug: String, file: String,
                 credit: String = "Evan-Amos / Wikimedia Commons",
                 license: String = "Public domain") {
            guard let item = bySlug[slug] else { return }
            let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
            let url = "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=800"
            guard item.imageURLString != url else { return }
            item.imageURLString = url
            item.imageCredit = credit
            item.imageLicense = license
        }

        set("2600-4switch", file: "Atari-2600-Wood-4Sw-Set.png")
        set("nes-001", file: "NES-Console-Set.png")
        set("sns-001", file: "SNES-Mod1-Console-Set.jpg")
        set("gen-model-1", file: "Sega-Genesis-Mod1-Set.jpg")
        set("gb-dmg-01", file: "Game-Boy-FL.png")
        set("nus-001", file: "Nintendo-64-wController-L.jpg")
        set("scph-1001", file: "PSX-Console-wController.jpg")
        set("hkt-3020", file: "Dreamcast-Console-Set.jpg", license: "CC BY-SA 3.0")
        set("scph-30001", file: "PS2-Fat-Console-Set.jpg")
        set("dol-001", file: "GameCube-Console-Set.png")
    }

    // MARK: - Collection

    @MainActor
    static func makeCollection(catalog: [CatalogItem]) -> [CollectionItem] {
        var bySlug: [String: CatalogItem] = [:]
        for c in catalog { bySlug[c.slug] = c }

        func daysAgo(_ n: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now
        }

        var entries: [CollectionItem] = []

        entries.append(CollectionItem(
            catalogItem: bySlug["sns-001"], status: .owned, condition: .veryGood,
            completeness: .loose, pricePaid: 75, dateAcquired: daysAgo(220),
            acquisitionSource: .onlineMarketplace, storageLocation: "Shelf A · Bin 2",
            notes: "Slight yellowing on the top shell. Retr0brite candidate.",
            dateAdded: daysAgo(220)))

        entries.append(CollectionItem(
            catalogItem: bySlug["snes-chrono-trigger"], status: .owned, condition: .good,
            completeness: .completeInBox, hasBox: true, hasManual: true, hasInserts: true,
            pricePaid: 240, dateAcquired: daysAgo(140), acquisitionSource: .localSeller,
            storageLocation: "Display case", notes: "Box has shelf wear on the top-right corner. Map included.",
            playStatus: .completed, dateAdded: daysAgo(140)))

        entries.append(CollectionItem(
            catalogItem: bySlug["nes-001"], status: .owned, condition: .good,
            completeness: .boxedNoManual, hasBox: true, hasOriginalPackaging: true,
            pricePaid: 90, dateAcquired: daysAgo(400), acquisitionSource: .gameStore,
            storageLocation: "Shelf A · Bin 1", notes: "72-pin connector replaced. Box is rough but present.",
            dateAdded: daysAgo(400)))

        entries.append(CollectionItem(
            catalogItem: bySlug["n64-oot"], status: .owned, condition: .veryGood,
            completeness: .completeInBox, hasBox: true, hasManual: true,
            pricePaid: 65, dateAcquired: daysAgo(65), acquisitionSource: .onlineMarketplace,
            storageLocation: "Shelf B · Bin 4", notes: "Grey cart, not gold. Save battery still holds.",
            playStatus: .playing, dateAdded: daysAgo(65)))

        entries.append(CollectionItem(
            catalogItem: bySlug["ps1-sotn"], status: .owned, condition: .veryGood,
            completeness: .completeInBox, hasBox: true, hasManual: true,
            pricePaid: 140, dateAcquired: daysAgo(30), acquisitionSource: .onlineMarketplace,
            estimatedValueOverride: 185, storageLocation: "Display case",
            notes: "Jewel-case printing. Manual near-mint.", playStatus: .backlog,
            dateAdded: daysAgo(30)))

        entries.append(CollectionItem(
            catalogItem: bySlug["gcn-smash-melee"], status: .owned, condition: .good,
            completeness: .loose, pricePaid: 22, dateAcquired: daysAgo(500),
            acquisitionSource: .gift, storageLocation: "Shelf B · Bin 5",
            notes: "Disc has light hairlines, plays fine.", playStatus: .playing,
            dateAdded: daysAgo(500)))

        entries.append(CollectionItem(
            catalogItem: bySlug["gen-model-2"], status: .owned, condition: .veryGood,
            completeness: .loose, pricePaid: 35, dateAcquired: daysAgo(310),
            acquisitionSource: .localSeller, storageLocation: "Shelf A · Bin 3",
            notes: "Includes one 3-button pad and RF only — need an A/V cable.",
            dateAdded: daysAgo(310)))

        entries.append(CollectionItem(
            catalogItem: bySlug["gb-tetris"], status: .owned, condition: .good,
            completeness: .loose, pricePaid: 9, dateAcquired: daysAgo(120),
            acquisitionSource: .gameStore, storageLocation: "Handheld drawer",
            notes: "Label is clean. Classic.", playStatus: .completed, dateAdded: daysAgo(120)))

        // Wishlist
        entries.append(CollectionItem(
            catalogItem: bySlug["snes-super-metroid"], status: .wishlist,
            notes: "Want a complete-in-box copy under $180.", dateAdded: daysAgo(18)))

        entries.append(CollectionItem(
            catalogItem: bySlug["gen-psiv"], status: .wishlist,
            notes: "Grail. CIB only. Watching auctions.", dateAdded: daysAgo(9)))

        entries.append(CollectionItem(
            catalogItem: bySlug["n64-goldeneye"], status: .wishlist,
            notes: "Loose is fine for the party shelf.", dateAdded: daysAgo(3)))

        // For sale
        entries.append(CollectionItem(
            catalogItem: bySlug["ps2-gow"], status: .forSale, condition: .good,
            completeness: .completeInBox, hasBox: true, hasManual: true,
            pricePaid: 5, dateAcquired: daysAgo(700), estimatedValueOverride: 20,
            storageLocation: "Sell box", notes: "Have a duplicate. Greatest Hits copy.",
            dateAdded: daysAgo(700)))

        return entries
    }
}
