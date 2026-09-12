# Backlog / ideas

Running list of enhancements — not commitments. Near-term implementation TODOs
also live in [`api/README.md`](api/README.md) and [`apple/README.md`](apple/README.md).

## Platform drill-down & adding to collection

- ~~**Bulk add**~~ — done: "Select" mode → checkbox rows + a bottom bar that
  adds the whole selection with one shared completeness.
- ~~**Quick-condition add**~~ — done: the `+` presents `QuickAddSheet` with
  completeness (Loose/Boxed/CIB/Sealed) + condition before inserting.
- ~~**"Remaining value"**~~ — done: `SystemSummary.remainingValue`, shown as
  "To finish" in the summary strip.
- ~~**Sort options** in the drill-down~~ — done: Title / Release Year /
  Publisher / Value in the header filter menu.
- ~~**A–Z section index / scrubber**~~ — done (iOS): `AZScrubber` on the trailing
  edge when title-sorted with 40+ rows. macOS keeps its scrollbar.
- ~~**Hover actions on macOS rows**~~ — done: wishlist star appears on row hover
  (macOS); leading swipe on iOS.
- ~~**Wishlist as a first-class scope**~~ — done: the drill-down scope is now
  **Owned / Wanted / Missing / All** (absolute filters); `mode` only picks the
  default. Wishlist stays a top-level section for the flat cross-platform view.
- ~~**Merge `SystemGamesList` + `PlatformDetailView`**~~ — done: `SystemGamesList`
  is the one platform screen (collapsible "About this system" mini-wiki +
  scope/kind/sort + the catalog list). `PlatformDetailView` and the top-level
  Platforms section are gone — the app is collection-first.

## Collection & items

- ~~`PhotosPicker` → `CollectionItem.photoData`~~ — done: Photos section in the
  edit form (multi-select, capped, ImageIO-downscaled to 1600px JPEG).
- **Barcode scan to add** (iOS `DataScannerViewController`). Needs an
  `NSCameraUsageDescription` in the target's Info.plist (user has to add it) and
  device testing — not doable headless.
- Multiple copies / variant handling surfaced in the UI (model already supports it).
- ~~**CSV export**~~ — done: `CollectionCSV` + "Export as CSV…" in the Backup menu.
- Per-item **price sparkline** + collection **value-over-time chart** — both need
  the feed to carry price history / periodic snapshots.

## Data feed & backend

- **Disc-system catalogs** (PS1 / PS2 / Dreamcast / GameCube) — `ingest/igdb.mjs`
  is written and handles them; blocked only on `IGDB_CLIENT_ID` /
  `IGDB_CLIENT_SECRET`. Run it, review the diff, commit the generated JSON.
- ~~Implement `api/build/pricing/pricecharting.mjs`~~ — done, but **dormant**:
  needs `PRICECHARTING_TOKEN` (paid) **and** `PRICECHARTING_ENABLE=1`, then fills
  in prices for un-priced games newest-first, `PRICECHARTING_MAX` calls/night.
  Until the user enables it the ~3,500 imported games still show "no pricing yet".
  Still worth doing: the nightly CSV path (Legendary tier) instead of per-item.
- **Bulk-sync perf** — first `CatalogSyncService` sync now inserts ~3,600 rows on
  the main actor (chunked saves + `Task.yield` every 400, change-detection after).
  If the catalog keeps growing, move `reconcile` to a background `ModelContext` /
  `ModelActor`, or split the feed per-platform and sync lazily.
- ~~Invert source of truth~~ — done: `api/data/curated.json` is authored
  directly, `api/build/sync-seed.mjs` → `Resources/CatalogSeed.json`, decoded by
  `CatalogSeedStore` (covered by `RetroStacksTests/CatalogSeedTests`).
- Slug scheme: curated uses short slugs (`nes-smb3`), generated uses
  `nes-super-mario-bros-3`. Merge dedups by normalized title, but a full switch to
  the generated scheme would need a one-time slug migration for existing rows.
- Implement `api/build/sources/{mysql,supabase}.mjs` when the catalog outgrows the
  file-based source.
- Own image CDN (R2 / S3) — drop the Wikimedia / Libretro hot-links, broaden
  coverage, normalize sizes; many imported games have no boxart on the CDN.

## Multi-user (Phase 1+)

Phase 0 groundwork is done (`CollectionItem.updatedAt` / `deletedAt`,
`AccountService`, `CollectionSyncEngine` + `Sync.engine`, `CollectionActions`).
Plan + schema written up in [`supabase/README.md`](supabase/README.md) /
[`supabase/schema.sql`](supabase/schema.sql) — **blocked on the user creating the
Supabase project** and handing back the project URL + anon key.

- Supabase: run `schema.sql`, then `SupabaseAccountService` +
  `SupabaseCollectionSyncEngine`, magic-link sign-in sheet, a sync coordinator
  (last-write-wins by `updatedAt`, tombstones carry deletes). Photos go to a
  Supabase Storage bucket, not inlined base64.
- Companion **website** on `retrostacks.com` — same schema, Supabase JS client;
  read-only mirror first, then editing.
- Prune old tombstones after a confirmed successful sync.

## Accessibility

Near-zero today: two `.accessibilityLabel` calls in the whole app (the A–Z
scrubber, the status badge icon), zero `.accessibilityIdentifier` anywhere, and
~23 icon-only controls (add buttons, wishlist stars, toolbar icons, the sort/
kind menu trigger) with no spoken label — they lean on `.help()`, which is a
macOS mouse-hover tooltip and isn't read by VoiceOver on either platform. Found
this the hard way (2026-09-12): trying to click-test the platform-breakdown
navigation on macOS, `System Events` couldn't see any queryable UI elements to
act on — no identifiers to hang automation off of. Two real reasons to fix
this, not one: actual VoiceOver support, and reliable UI automation (my own
testing, and eventually XCUITest).

Design constraint from the user: identifiers must be centralized and **stable
across rebuilds and reorganizing views** — not autogenerated, not positional
(never `"row-\(index)"`, which silently changes meaning the moment a list is
resorted or filtered), low-complexity to extend as screens move around.

Proposed shape — one new file, `App/AccessibilityID.swift`, namespaced enums
mirroring the existing `Views/<Feature>/` folders (`AccessibilityID.Dashboard`,
`AccessibilityID.Collection`, `AccessibilityID.Catalog`, …):
- **Static** ids for one-off chrome: `AccessibilityID.Dashboard.ownedItemsTile`,
  `.SystemScreen.scopePicker`, `.SystemScreen.sortMenu` — plain `String`
  constants, trivially stable.
- **Keyed** ids for repeated content, derived from the model's own durable
  identity rather than array position: `AccessibilityID.Collection.systemRow(platform.slug)`,
  `.systemTile(catalogItem.slug)`, `.collectionRow(item.resolvedExportID)` — a
  small `(String) -> String` helper per case, so a reorder/resort never changes
  what a given row is addressed as.
- Apply `.accessibilityIdentifier(_:)` at each corresponding view; pair it with
  a real `.accessibilityLabel` (+ `.accessibilityHint` where the action isn't
  obvious from the label alone) on every icon-only control — start with the
  ~23 already found via `grep -rn "labelStyle(.iconOnly)\|Image(systemName:"`.
- Large surface area (touches nearly every custom view) — do it screen by
  screen rather than one sweep, starting wherever the next real feature work
  already has a view open.

## Platform & polish

- ~~Surface background API failures in the UI~~ — done: `AppStatusCenter` +
  corner `AppStatusBadge`. Wired for catalog sync + price refresh; `Supabase*`
  engines should `report(.collectionSync, …)` / `clear` the same way.
- iPad: a proper 3-column layout for the collection drill-down.
- EU / JP region switch (`Region` already modeled).
- Revisit the `GeometryReader` breakdown bar if the `_NSDetectedLayoutRecursion`
  log ever turns into visible jank.
