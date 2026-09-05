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
VideoGameTracker/
├── App/            App entry, RootView shell, sidebar, layout metrics, nav destinations
├── Models/         SwiftData @Model types + Enums
├── ViewModels/     @Observable filter/sort state (CollectionList, CatalogBrowse)
├── Services/       SampleData (mock seed + preview container), CollectionStats
└── Views/
    ├── Dashboard/
    ├── Collection/ section split, Table, detail, edit form, add-from-catalog sheet
    ├── Catalog/    section split, item detail
    ├── Platforms/  section split, platform detail
    └── Components/  thumbnails, badges, rows, cards, stat tiles, formatting
```

## Wiring it into Xcode (one-time)

Per `CLAUDE.md`, no `.xcodeproj` / `.pbxproj` is committed. Xcode's new-project
wizard won't merge into an existing source folder, so the setup parks the
sources aside, creates the project, then merges them back:

1. **Xcode → File → New → Project → Multiplatform → App.**
   - Product Name: `VideoGameTracker`
   - Storage: **None** (we bring our own `ModelContainer`)
   - Location: the `apple/` directory. Uncheck **Create Git repository**.
   - This produces `apple/VideoGameTracker.xcodeproj` and a fresh
     `apple/VideoGameTracker/` folder with a few stub files.
2. Our sources get merged into that `VideoGameTracker/` folder; Xcode's stub
   `ContentView.swift` / `Item.swift` are deleted, our `App/VideoGameTrackerApp.swift`
   replaces Xcode's stub, and Xcode's `Assets.xcassets` + `Preview Content` are kept.
3. The multiplatform template already makes `VideoGameTracker/` a **File System
   Synchronized group**, so every `.swift` file under it is in the target
   automatically — nothing to add by hand.
4. Deployment targets default to **iOS 26.0 / macOS 26.0** under Xcode 26; keep
   them there (or adjust `LayoutMetrics` / availability for an earlier SDK).
5. Build & run. First launch seeds the mock data via
   `SampleData.seedIfNeeded(_:)`; delete the app / its store to re-seed.

Every view has a `#Preview` backed by `SampleData.previewContainer()` (in-memory),
so previews work immediately.

## Next steps (suggested)

- Replace `SampleData` with a `CatalogRepository` protocol + REST implementation
  once the domain/API is registered; the mock stays as the preview/offline path.
- Add `PhotosPicker` binding to `CollectionItem.photoData`.
- Real box-art assets keyed by `CatalogItem.imageName`.
- Region switching for EU / JP (`Region` enum + `Platform.regionsAvailable` already model it).
- Valuation history + charts (Swift Charts) on the collection detail.
