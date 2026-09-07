# Backlog / ideas

Running list of enhancements — not commitments. Near-term implementation TODOs
also live in [`api/README.md`](api/README.md) and [`apple/README.md`](apple/README.md).

## Platform drill-down & adding to collection

- **Bulk add** — multi-select in the *Missing* scope, "Add N to collection".
- ~~**Quick-condition add**~~ — done: the `+` presents `QuickAddSheet` with
  completeness (Loose/Boxed/CIB/Sealed) + condition before inserting.
- ~~**"Remaining value"**~~ — done: `SystemSummary.remainingValue`, shown as
  "To finish" in the summary strip.
- ~~**Sort options** in the drill-down~~ — done: Title / Release Year /
  Publisher / Value in the header filter menu.
- **A–Z section index / scrubber** for long platform catalogs (macOS + iOS), like
  Retro Game Collector's edge scrubber.
- **Hover actions on macOS rows** — reveal Add / Wishlist / Open on hover.
- **Wishlist as a first-class scope** — Owned / Wanted / Missing / All, with a
  per-row quick wishlist toggle.
- **Merge `SystemGamesList` + `PlatformDetailView`** — they overlap; one
  "platform screen" with scope + kind + summary + the console/game/accessory split.

## Collection & items

- `PhotosPicker` → `CollectionItem.photoData` (field already exists, no UI yet).
- **Barcode scan to add** (iOS `DataScannerViewController`).
- Multiple copies / variant handling surfaced in the UI (model already supports it).
- **CSV export** alongside the JSON archive (for spreadsheets / other trackers).
- Per-item **price sparkline** + collection **value-over-time chart** — both need
  the feed to carry price history / periodic snapshots.

## Data feed & backend

- **Disc-system catalogs** (PS1 / PS2 / Dreamcast / GameCube) — the
  `api/build/ingest/libretro.mjs` script can list them, but libretro-database has
  no genre/year/publisher for redump systems. Needs IGDB or TheGamesDB (both need
  a key) for real metadata before pulling ~5k more games.
- Implement `api/build/pricing/pricecharting.mjs` (token; 1 req/sec, or nightly CSV).
  Right now only the ~66 curated items have prices; the ~3,500 imported games
  show "no pricing yet".
- **Bulk-sync perf** — first `CatalogSyncService` sync now inserts ~3,600 rows on
  the main actor (chunked saves + `Task.yield` every 400, change-detection after).
  If the catalog keeps growing, move `reconcile` to a background `ModelContext` /
  `ModelActor`, or split the feed per-platform and sync lazily.
- Invert source of truth: bundle `curated.json` in the app, have `SampleData`
  decode it (kill the Swift/JSON duplication).
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

- Supabase: Postgres schema + RLS, `SupabaseAccountService` +
  `SupabaseCollectionSyncEngine`, magic-link sign-in sheet, a sync coordinator
  (last-write-wins by `updatedAt`, tombstones carry deletes).
- Companion **website** on `retrostacks.com` — same schema, Supabase JS client;
  read-only mirror first, then editing.
- Prune old tombstones after a confirmed successful sync.

## Platform & polish

- iPad: a proper 3-column layout for the collection drill-down.
- EU / JP region switch (`Region` already modeled).
- Revisit the `GeometryReader` breakdown bar if the `_NSDetectedLayoutRecursion`
  log ever turns into visible jank.
