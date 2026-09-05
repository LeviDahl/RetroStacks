# Video Game Tracker

Cross-platform (macOS / iPadOS / iOS) tracker for retro video game **systems,
games, and accessories** — a personal collection manager backed by a
comprehensive reference catalog.

This repo currently contains **UI wiring + mock data only**. No network layer
yet; a real API/DB will replace `SampleData` later.

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

## Wiring it into Xcode (targets not yet assigned)

Per `CLAUDE.md`, no `.xcodeproj` / `.pbxproj` was created or edited. To build:

1. **Xcode → File → New → Project → Multiplatform → App.**
   - Product Name: `VideoGameTracker`
   - Storage: **SwiftData**
   - Location: this folder (so the project sits next to the `VideoGameTracker/`
     source folder).
2. Delete the stub `ContentView.swift` / `*App.swift` / `Item.swift` Xcode
   generates.
3. In the Project navigator, add the existing `VideoGameTracker/` folder as a
   **folder reference with "Create folder synchronization"** (Xcode 16+ File
   System Synchronized group) so every `.swift` file here is picked up
   automatically. Confirm the group's target membership is the app target for all
   three destinations (My Mac / iPhone / iPad).
4. Set deployment targets to **iOS 26.0 / macOS 26.0** (or adjust
   `LayoutMetrics` / availability if you build against an earlier SDK).
5. Build & run. First launch seeds the mock data via
   `SampleData.seedIfNeeded(_:)`; delete the app / DB to re-seed.

Every view has a `#Preview` backed by `SampleData.previewContainer()` (in-memory),
so previews work before the app target exists.

## Next steps (suggested)

- Replace `SampleData` with a `CatalogRepository` protocol + REST implementation
  once the domain/API is registered; the mock stays as the preview/offline path.
- Add `PhotosPicker` binding to `CollectionItem.photoData`.
- Real box-art assets keyed by `CatalogItem.imageName`.
- Region switching for EU / JP (`Region` enum + `Platform.regionsAvailable` already model it).
- Valuation history + charts (Swift Charts) on the collection detail.
