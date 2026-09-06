# Video Game Tracker — Apple app

Native SwiftUI app for **macOS / iPadOS / iOS**: a personal collection manager
for retro video game **systems, games, and accessories**, backed by a
comprehensive reference catalog.

This directory currently contains **UI wiring + mock data only**. No network
layer yet; a real API/DB (see [`../api/`](../api/)) will replace `SampleData`.

Everything below is relative to this `apple/` directory. Sources live in
`VideoGameTracker/`; the `.xcodeproj` is not committed (see setup below).

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

**Verified:** `xcodebuild … -destination 'platform=macOS' build` → `BUILD SUCCEEDED`.
Full source also type-checks under Swift 6 against the macOS 26 and iOS 26 SDKs.

## Next steps (suggested)

- Replace `SampleData` with a `CatalogRepository` protocol + REST implementation
  once the domain/API is registered; the mock stays as the preview/offline path.
- Add `PhotosPicker` binding to `CollectionItem.photoData`.
- Real box-art assets keyed by `CatalogItem.imageName`.
- Region switching for EU / JP (`Region` enum + `Platform.regionsAvailable` already model it).
- Valuation history + charts (Swift Charts) on the collection detail.
