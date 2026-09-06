# RetroStacks — Apple app

Native SwiftUI app for **macOS / iPadOS / iOS**: a personal collection manager
for retro video game **systems, games, and accessories**, backed by a
comprehensive reference catalog.

Everything below is relative to this `apple/` directory. Sources live in
`VideoGameTracker/`; the `.xcodeproj` is committed at `apple/`.

> **Rename status:** the product name is **RetroStacks** (shown in-app). The
> Xcode target, scheme, bundle id, source folder, and the Git repo are still
> `VideoGameTracker` — see *Renaming to RetroStacks* at the bottom.

## Status

| Area | State |
| --- | --- |
| Data model (SwiftData) | ✅ `Platform`, `CatalogItem`, `CollectionItem` |
| Mock catalog | ✅ 10 US platforms · ~30 consoles · ~40 games · ~25 accessories (`Services/SampleData.swift`) |
| Dashboard | ✅ stats, value-by-platform, recent / most valuable |
| My Collection | ✅ list (iOS) / sortable `Table` (macOS), filters, detail, edit form |
| Wishlist | ✅ same surface, `.wishlist` status |
| Catalog browser | ✅ poster grid (macOS) / list (iOS), filters, detail, "Add to Collection" |
| Platforms | ✅ per-system browsing with console/game/accessory tabs |
| Photos, barcode scan, valuation API, EU/JP regions | ⛔️ stubbed in the model, no UI |

## Platform layout philosophy

macOS is **not** a stretched iPhone screen:

- Three real columns (`sidebar → list → detail`) via nested `NavigationSplitView`.
- Collection uses a dense, multi-column `Table`; catalog & platforms use
  adaptive **poster/card grids** that add columns as the window widens.
- Generous margins/spacing (`LayoutMetrics`, 28pt edges vs 16pt on iOS).
- Detail panes are always visible; iOS pushes them and uses sheets.

iPhone (compact width) falls back to a `TabView`. iPad uses the split layout.

## Project structure

```
apple/
├── VideoGameTracker.xcodeproj     Multiplatform App target (macOS / iPadOS / iOS)
├── VideoGameTracker/              File System Synchronized group — all files below are in the target
│   ├── Assets.xcassets           AppIcon + AccentColor (from the template)
│   ├── App/                      App entry, RootView shell, sidebar, layout metrics, nav destinations
│   ├── Models/                   SwiftData @Model types + Enums
│   ├── ViewModels/               @Observable filter/sort state (CollectionList, CatalogBrowse)
│   ├── Services/                 SampleData (mock seed + preview container), CollectionStats
│   │   └── Pricing/              canonical price schema + provider adapters + PricingService
│   └── Views/
│       ├── Dashboard/
│       ├── Collection/           section split, Table, detail, edit form, add-from-catalog sheet
│       ├── Catalog/              section split, item detail
│       ├── Platforms/            section split, platform detail
│       └── Components/           thumbnails, badges, rows, cards, stat tiles, formatting
├── VideoGameTrackerTests/         (template stub)
└── VideoGameTrackerUITests/       (template stub)
```

## Building

```
open apple/VideoGameTracker.xcodeproj
```

or from the command line:

```
xcodebuild -project apple/VideoGameTracker.xcodeproj -scheme VideoGameTracker \
  -destination 'platform=macOS' build
```

- Multiplatform **App** target, Storage: None — the app creates its own
  `ModelContainer` in `App/VideoGameTrackerApp.swift`.
- `VideoGameTracker/` is a **File System Synchronized group**: drop a `.swift`
  file anywhere under it and it's in the target automatically, no `.pbxproj` edit.
- Deployment targets default to **macOS 26 / iOS 26** (Xcode 26). The iOS
  Simulator runtime must be installed (Xcode → Settings → Components) to build
  the iOS slice; the macOS build works out of the box.
- First launch seeds the mock data via `SampleData.seedIfNeeded(_:)`; delete the
  app / its store to re-seed. Every view has a `#Preview` on
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

`CatalogItem` carries `imageURLString` / `imageCredit` / `imageLicense`.
`SampleData.attachConsolePhotos` fills these for each platform's primary console
model from Wikimedia Commons (`Special:FilePath` stable redirect; mostly Evan
Amos public-domain shots, Dreamcast is CC BY-SA 3.0 and shows attribution).
`ItemThumbnail` resolves bundled asset → remote `AsyncImage` (shared `URLCache`
bumped to 256 MB disk in `configureImageCache()`) → SF Symbol placeholder.
Variants, games, and accessories still use the placeholder — a real image service
is on the backlog in [`../api/README.md`](../api/README.md#image-hosting-backlog).

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

- Replace `SampleData` with a `CatalogRepository` protocol + REST implementation
  once the domain/API is registered; the mock stays as the preview/offline path.
- Add a `RemotePricingProvider` (hits our `/price-guide` endpoint) and drop it in
  ahead of `SampleGuideProvider` in `PricingService.makeDefault()`.
- Add `PhotosPicker` binding to `CollectionItem.photoData`.
- Real box-art assets keyed by `CatalogItem.imageName`.
- Region switching for EU / JP (`Region` enum + `Platform.regionsAvailable` already model it).
- Valuation history + charts (Swift Charts) on the collection detail.

## Renaming to RetroStacks

Done code-side (the in-app title). The rest is mechanical but touches the project
file and GitHub, so it's a deliberate step:

1. **Xcode** → select the project → rename the **`VideoGameTracker` target** to
   `RetroStacks` (Xcode offers to rename the scheme and the synchronized group
   folder too — accept). Set **Bundle Identifier** to `com.<you>.retrostacks` and
   **Display Name** to `RetroStacks`.
2. `VideoGameTrackerApp.swift` → `struct RetroStacksApp: App` (and its file name).
   `VideoGameTrackerTests` / `UITests` targets rename similarly if you keep them.
3. **Repo**: `gh repo rename RetroStacks` then
   `git remote set-url origin git@github.com:LeviDahl/RetroStacks.git`.
   Optionally rename the local folders `videogametracker/` → `retrostacks/` and
   `apple/VideoGameTracker/` → `apple/RetroStacks/`.
4. Grep the tree for `VideoGameTracker` and fix the stragglers (mostly comments
   and these READMEs).

No hurry — everything builds and runs under the current names.
