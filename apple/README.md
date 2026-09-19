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
| Seed catalog | ✅ 19 platforms (gen 2–6) · ~66 curated entries as the first-launch seed (`api/data/curated.json` → `Resources/CatalogSeed.json` via `CatalogSeedStore`); the full ~22,000-item catalog syncs in afterward from Supabase (`SupabaseCatalogRepository`) |
| Dashboard | ✅ stats, value-by-platform, recent / most valuable |
| My Collection | ✅ list (iOS) / sortable `Table` (macOS), filters, detail, edit form |
| Wishlist | ✅ same surface, `.wishlist` status |
| Catalog browser | ✅ system-first (pick a platform, then browse/search within it) with a flat cross-platform search as the escape hatch; poster grid (macOS) / list (iOS), filters, detail, "Add to Collection" |
| System screen | ✅ `SystemGamesList` — one screen per platform: collapsible "About" mini-wiki, Owned/Wanted/Missing/All scope, kind + sort, quick-add modal (completeness/condition), bulk add, wishlist toggle, A–Z scrubber |
| Barcode scan | ✅ iOS only (`DataScannerViewController`/VisionKit) — matches a scanned UPC against the catalog; not verified on a real device yet (Simulator has no camera) |
| Photos | ✅ `PhotosPicker` in the edit form (downscaled JPEG in `photoData`) |
| Backup | ✅ JSON archive (round-trip) + CSV export |
| Multi-device sync | ✅ optional Supabase sign-in (email magic link, paste-back) syncs the collection across devices; local-first either way — see [`../supabase/README.md`](../supabase/README.md) |
| Failure surfacing | ✅ `AppStatusCenter` + a corner `AppStatusBadge` — background failures (catalog sync, price refresh, collection sync) show one small icon with detail + Retry; auto-clears on the next success |
| Accessibility | 🚧 in progress, driven by real `performAccessibilityAudit()` runs (not guesses) — see `BACKLOG.md`'s Accessibility section for current findings per screen |
| Regions | ✅ catalog items carry `regions`; North America only by default, a per-screen "non-NA regions" toggle (`system.showNonNARegions`) shows EU/JP. The ingested JSON has region data for all 19 platforms, but the live Supabase rows need a `migrate-catalog-to-supabase.mjs` run to pick it up (checked 2026-09-19: live `regions` was still null on every row) |
| Catalog curation | ✅ hide items personally, or (admins) exclude them catalog-wide; a "review candidates" filter surfaces likely bootlegs/hacks |
| Valuation API | ⛔️ `PriceChartingProvider` is mapping-complete but needs a paid token to activate |
| Performance | ✅ heavy per-screen work (system summaries, Catalog filter/sort, platform rows) runs in `@ModelActor` background actors built via `@concurrent` helpers, with stale-while-revalidate caches (`SystemSummariesCache`, `PlatformOverviewCache`); images are downsampled and byte-budgeted (`CachedAsyncImage` / `ImageMemoryCache`) |

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
│   ├── Assets.xcassets           AppIcon, AccentColor + semantic colors (AccentGold/Green/Red/Blue/Purple/Orange/Mint,
│   │                              MutedTextCompliant)
│   ├── App/                      App entry, RootView shell (split/tab layout), sidebar, layout metrics,
│   │                              accessibility identifiers, muted-text contrast switch, nav destinations
│   ├── Models/                   SwiftData @Model types + Enums
│   ├── ViewModels/               @Observable filter/sort state (CollectionList, CatalogBrowse)
│   ├── Resources/                CatalogSeed.json (synced from api/data/curated.json) + SampleCollection.json
│   ├── Services/                 CatalogSeedStore + SampleData (seed/preview), CollectionStats, AppLog,
│   │                              AppStatusCenter
│   │   ├── Catalog/               SupabaseCatalogRepository + CatalogSyncService (fetch/upsert), admin/custom-item
│   │   │                          services, background actors (CatalogQueryActor, CollectionSummariesActor),
│   │   │                          CatalogBrowseFilter, SystemSummariesCache / PlatformOverviewCache, BackendConfig
│   │   ├── Collection/            CollectionArchive (JSON backup), CollectionCSV, CollectionExport (lazy export
│   │   │                          documents), CollectionActions, PhotoImport
│   │   ├── Pricing/               canonical price schema + provider adapters + PricingService
│   │   └── Sync/                  AccountService, Supabase auth/session/sync-engine, SyncCoordinator
│   └── Views/
│       ├── Account/               sign-in sheet (magic link)
│       ├── Dashboard/
│       ├── Collection/            section split, Table, detail, edit form, the per-system screen,
│       │                          add-to-collection flow + quick-add (completeness, box/manual), barcode scanner (iOS)
│       ├── Catalog/               section split, item detail, custom-entry sheet
│       └── Components/            thumbnails, badges, rows, cards, stat tiles, toast, formatting
├── RetroStacksTests/               seed decode/insert, Supabase session + wire-format round-trips,
│                                    catalog sync, account-service init ordering, sync-coordinator merge logic,
│                                    background actors / caches / export laziness / image downsampling
└── RetroStacksUITests/             navigation regression coverage + a real, ratcheted accessibility audit
                                     (Dashboard, SystemGamesList, CollectionSection, CatalogSection,
                                     AddToCollectionFlow, SidebarView) + a multi-pass app walkthrough
                                     (leak-testing groundwork)
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

`ItemThumbnail` resolves bundled asset → `CachedAsyncImage` → SF Symbol
placeholder. `CachedAsyncImage` fetches off the main actor, downsamples with
ImageIO to ~3× the display size (never keeping a full-resolution bitmap), and
caches the result in `ImageMemoryCache` (byte-budgeted `NSCache`, 80 MB) so a
screen rebuilt on every sidebar switch doesn't reload its images; the shared
`URLCache` is bumped to 256 MB disk in `configureImageCache()`.
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
- ~~Multi-device collection sync~~ — done: Supabase Auth + Postgres, see
  [`../supabase/README.md`](../supabase/README.md). Not yet exercised with a
  real live sign-in — that's the next thing to actually do, not build.
- ~~Barcode scanning~~ — done (iOS/VisionKit); needs a real-device test, the
  Simulator has no camera.
- Real box-art assets keyed by `CatalogItem.imageName` (games currently use
  Libretro's thumbnail CDN, consoles use hot-linked Wikimedia Commons photos).
- Valuation history + charts (Swift Charts) on the collection detail — needs the
  feed to carry price history first.
- Finish the accessibility pass (see `BACKLOG.md`) and a real device VoiceOver
  check before calling any screen actually done.

## Rename history

Renamed from `VideoGameTracker` → `RetroStacks` (target, scheme, bundle id
`com.levidahlstrom.RetroStacks`, source folders, and the GitHub repo
`LeviDahl/RetroStacks`). During the move the renamed `project.pbxproj` was lost;
it was reconstructed from the last committed copy with a mechanical
`VideoGameTracker → RetroStacks` substitution (target / products / group paths /
bundle ids — the same result Xcode's rename had produced). Build settings
(`ENABLE_OUTGOING_NETWORK_CONNECTIONS`, `SWIFT_VERSION = 6.0`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) carried over intact.
