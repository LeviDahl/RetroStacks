# Backlog / ideas

Running list of enhancements — not commitments. Near-term implementation TODOs
also live in [`api/README.md`](api/README.md) and [`apple/README.md`](apple/README.md).

## Platform drill-down & adding to collection

- **Bulk add** — multi-select in the *Missing* scope, "Add N to collection".
- **Quick-condition add** — split the `+` into "Add loose / CIB / sealed" so a
  batch of adds isn't all `loose / Good`.
- **"Remaining value"** — total est. value of what you're *missing* on a platform
  ("how much to finish this set"), shown in the summary strip.
- **Sort options** in the drill-down — A–Z (current) / value / release year /
  recently added.
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

- Implement `api/build/sources/{mysql,supabase}.mjs` when the catalog outgrows the
  hand-maintained `api/data/catalog.json`.
- Implement `api/build/pricing/pricecharting.mjs` (token; 1 req/sec, or nightly CSV).
- Grow the real catalog beyond the ~60 sample items.
- Invert source of truth: bundle `catalog.json` in the app, have `SampleData`
  decode it (kill the duplication).
- Own image CDN (R2 / S3) — drop the Wikimedia / LibRetro hot-links, broaden
  coverage, normalize sizes.

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
