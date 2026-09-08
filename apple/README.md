# RetroStacks — Apple app

Native SwiftUI app for **macOS / iPadOS / iOS**: a personal collection manager
for retro video game **systems, games, and accessories**, backed by a
comprehensive reference catalog.

Everything below is relative to this `apple/` directory. Sources live in
`RetroStacks/`; `RetroStacks.xcodeproj` is committed alongside it.

## Status

| Area | State |
| --- | --- |
| Data model (SwiftData) | ✅ `Platform`, `CatalogItem`, `CollectionItem` |
| Seed catalog | ✅ 10 US platforms · ~66 curated entries — authored in `api/data/curated.json`, decoded from `Resources/CatalogSeed.json` by `CatalogSeedStore` |
| Dashboard | ✅ stats, value-by-platform, recent / most valuable |
| My Collection | ✅ list (iOS) / sortable `Table` (macOS), filters, detail, edit form |
| Wishlist | ✅ same surface, `.wishlist` status |
| Catalog browser | ✅ poster grid (macOS) / list (iOS), filters, detail, "Add to Collection" |
| System screen | ✅ `SystemGamesList` — one screen per platform: collapsible "About" mini-wiki, Owned/Wanted/Missing/All scope, kind + sort, quick-add modal, bulk add, wishlist toggle, A–Z scrubber |
| Photos | ✅ `PhotosPicker` in the edit form (downscaled JPEG in `photoData`) |
| Backup | ✅ JSON archive (round-trip) + CSV export |
| Failure surfacing | ✅ `AppStatusCenter` + a corner `AppStatusBadge` — background failures (catalog sync, price refresh) show one small icon with detail + Retry; auto-clears on the next success |
| Barcode scan, valuation API, EU/JP regions | ⛔️ stubbed in the model, no UI |

## Platform layout philosophy

macOS is **not** a stretched iPhone screen:

- Three real columns (`sidebar → list → detail`) via nested `NavigationSplitView`.
- Collection uses a dense, multi-column `Table`; the catalog browser uses
  adaptive **poster/card grids** that add columns as the window widens.
- Generous margins/spacing (`LayoutMetrics`, 28pt edges vs 16pt on iOS).
- Detail panes are always visible; iOS pushes them and uses sheets.

iPhone (compact width) falls back to a `TabView`. iPad uses the split layout.

## Project structure

```
apple/
├── RetroStacks.xcodeproj          Multiplatform App target (macOS / iPadOS / iOS)
├── RetroStacks/                   File System Synchronized group — all files below are in the target
│   ├── Assets.xcassets           AppIcon + AccentColor (from the template)
│   ├── App/                      App entry, RootView shell, sidebar, layout metrics, nav destinations
│   ├── Models/                   SwiftData @Model types + Enums
│   ├── ViewModels/               @Observable filter/sort state (CollectionList, CatalogBrowse)
│   ├── Resources/                CatalogSeed.json (synced from api/data/curated.json) + SampleCollection.json
│   ├── Services/                 CatalogSeedStore + SampleData (seed/preview), CollectionStats
│   │   └── Pricing/              canonical price schema + provider adapters + PricingService
│   └── Views/
│       ├── Dashboard/
│       ├── Collection/           section split, Table, detail, edit form, the per-system screen
│       ├── Catalog/              section split, item detail
│       └── Components/           thumbnails, badges, rows, cards, stat tiles, formatting
├── RetroStacksTests/              CatalogSeedTests (+ Fixtures/) — the seed decode/insert path
└── RetroStacksUITests/            (template stub)
```

## Building

```
open apple/RetroStacks.xcodeproj
```

or from the command line:

```
xcodebuild -project apple/RetroStacks.xcodeproj -scheme RetroStacks \
  -destination 'platform=macOS' build
```

- Multiplatform **App** target, Storage: None — the app creates its own
  `ModelContainer` in `App/RetroStacksApp.swift`.
- `RetroStacks/` is a **File System Synchronized group**: drop a `.swift`
  file anywhere under it and it's in the target automatically, no `.pbxproj` edit.
- Deployment targets default to **macOS 26 / iOS 26** (Xcode 26). The iOS
  Simulator runtime must be installed (Xcode → Settings → Components) to build
  the iOS slice; the macOS build works out of the box.
- First launch seeds from `Resources/CatalogSeed.json` via
  `SampleData.seedIfNeeded(_:)` → `CatalogSeedStore`; delete the app / its store
  to re-seed. Run `node api/build/sync-seed.mjs` after editing
  `api/data/curated.json`. Every view has a `#Preview` on
  `SampleData.previewContainer()` (in-memory).

### Project settings (done — for reference)

Toggled in Xcode by hand (per `CLAUDE.md`'s "no direct project-file edits"):

1. **macOS network access** — App Sandbox → *Outgoing Connections (Client)* = YES
   (`ENABLE_OUTGOING_NETWORK_CONNECTIONS`). Without it, Wikimedia photos and any
   pricing fetch fall back silently on macOS. iOS/iPadOS need nothing.
2. **Swift 6 language mode** — `SWIFT_VERSION = 6.0`. Combined with the template's
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the pricing schema types are
   explicitly `nonisolated` to stay usable off the main actor.

### Images

`CatalogItem` carries `imageURLString` / `imageCredit` / `imageLicense`, filled
in `SampleData` with hot-linked URLs (no backend, no keys):
- **Consoles** — `attachConsolePhotos`: Wikimedia Commons `Special:FilePath`
  stable redirect. Mostly Evan Amos public-domain shots; Dreamcast is CC BY-SA 3.0.
- **Games** — `attachGameBoxArt`: the Libretro thumbnails CDN
  (`thumbnails.libretro.com/<system>/Named_Boxarts/<No-Intro name>.png`). Each of
  the 31 sample titles was verified to resolve; a miss just shows the placeholder.
  This is publisher artwork — our own image layer is the long-term plan.

`ItemThumbnail` resolves bundled asset → remote `AsyncImage` (shared `URLCache`
bumped to 256 MB disk in `configureImageCache()`) → SF Symbol placeholder.
Console *variants* and accessories still use the placeholder — a self-hosted
image service is on the backlog in
[`../api/README.md`](../api/README.md#image-hosting-backlog).

### Pricing

`Services/Pricing/` holds a **provider-agnostic pricing schema** (shape adapted
from the PriceCharting API — see [`../api/README.md`](../api/README.md#pricing-adapter-layer--schema-already-lives-in-the-app))
and a set of **lite adapters** behind one protocol:

```
PriceQuery ──▶ [ PricingProvider ] ──▶ ProviderPriceReport
                    │
   PriceChartingProvider · EbayBrowseProvider · GGDealsProvider · SampleGuideProvider
                    │
            PricingService.merge(…) ──▶ PriceGuide   (one value per condition|kind)
```

- **`PricingService`** (`@MainActor`, `.shared`) runs providers in priority
  order, first-with-a-value wins, failures are skipped (redundancy), 6 h cache.
  `refresh(_:in:)` writes the result back onto `CatalogItem`'s cached
  `estimatedValue*` / `salesVolumeYearly` / `priceGuide*` fields so lists, stats
  and offline use stay synchronous.
- **`SampleGuideProvider`** is the live default: it echoes the seeded values, so
  the "Market Value" card on the catalog detail renders and the *Refresh* button
  works with zero configuration.
- **`PriceChartingProvider`** is mapping-complete; set `PRICECHARTING_TOKEN` in
  the Run scheme's environment (or inject a token) and it activates. Prices come
  as integer pennies; 1 req/sec.
- **`EbayBrowseProvider` / `GGDealsProvider`** are stubs showing the seam.
- The schema files import only `Foundation` (types are `nonisolated` so models
  and future background contexts can use them) — ready to lift into a package.

**Verified:** `xcodebuild … -destination 'platform=macOS' build` → `BUILD SUCCEEDED`.
Full source also type-checks under Swift 6 against the macOS 26 and iOS 26 SDKs.

## Next steps (suggested)

- ~~Replace `SampleData` with a `CatalogRepository` + remote implementation~~ —
  done: `RemoteCatalogRepository` + `CatalogSyncService`; `SampleData` is now the
  first-launch seed + offline fallback + previews.
- ~~Add a `RemotePricingProvider`~~ — done, ahead of `SampleGuideProvider`.
- ~~Add `PhotosPicker` binding to `CollectionItem.photoData`~~ — done.
- Real box-art assets keyed by `CatalogItem.imageName`.
- Region switching for EU / JP (`Region` enum + `Platform.regionsAvailable` already model it).
- Valuation history + charts (Swift Charts) on the collection detail — needs the
  feed to carry price history first.

## Rename history

Renamed from `VideoGameTracker` → `RetroStacks` (target, scheme, bundle id
`com.levidahlstrom.RetroStacks`, source folders, and the GitHub repo
`LeviDahl/RetroStacks`). During the move the renamed `project.pbxproj` was lost;
it was reconstructed from the last committed copy with a mechanical
`VideoGameTracker → RetroStacks` substitution (target / products / group paths /
bundle ids — the same result Xcode's rename had produced). Build settings
(`ENABLE_OUTGOING_NETWORK_CONNECTIONS`, `SWIFT_VERSION = 6.0`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) carried over intact.
