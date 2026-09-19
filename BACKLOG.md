# Backlog / ideas

Running list of enhancements — not commitments. **Only open work lives here.**
Everything already built, fixed, or decided is in
[`FEATURES.md`](FEATURES.md) (the detailed, dated history — including *why*
things were done the way they were). Near-term implementation TODOs also live
in [`api/README.md`](api/README.md) and [`apple/README.md`](apple/README.md).

Add new ideas here rather than letting them evaporate mid-task; when something
ships, move its entry to `FEATURES.md`.

## Collection & items

- Multiple copies / variant handling surfaced in the UI (model already supports it).
- **Partial box/manual state.** `CollectionItem.hasBox`/`.hasManual` (and
  `.hasInserts`/`.hasOriginalPackaging`) are plain booleans today — no way to
  note "have it, but it's not complete" (a manual missing pages, a box
  without flaps/inserts, only some of the original pieces). A simple
  checkbox/button per field to flag "incomplete/partial" alongside the
  existing yes/no would cover this without a bigger redesign of the
  completeness model.
- Per-item **price sparkline** + collection **value-over-time chart** — both need
  the feed to carry price history / periodic snapshots.
- **Barcode scan needs a real-device test.** `BarcodeScannerView` (iOS,
  VisionKit `DataScannerViewController`) is build-verified and code-reviewed
  only — the Simulator has no camera. See FEATURES.md → Collection & items.

## Data feed & backend

- Slug scheme: curated uses short slugs (`nes-smb3`), generated uses
  `nes-super-mario-bros-3`. Merge dedups by normalized title, but a full switch to
  the generated scheme would need a one-time slug migration for existing rows.
- Implement `api/build/sources/{mysql,supabase}.mjs` when the catalog outgrows the
  file-based source.
- Own image CDN (R2 / S3) — drop the Wikimedia / Libretro hot-links, broaden
  coverage, normalize sizes; many imported games have no boxart on the CDN.
- **Open question — hand-curated seed items for the 9 newer platforms.** The
  original 10 got curated hardware/notable variants in `curated.json`; the 9
  added 2026-09-18 lean entirely on IGDB data so far. Whether they need the
  same treatment is undecided.

## Catalog curation

- **Admin surface for viewing/restoring excluded items — not started.**
  `admin_restore_catalog_items` can only be reached by knowing the exact slug;
  there's no in-app list of what's excluded (3,113 rows as of 2026-09-19). Want
  at minimum a browsable "excluded on this platform" list (`deleted_at is not
  null`, `owner_user_id is null` — `SupabaseCatalogRepository` filters these
  out on purpose) with a restore action per row.
- **`promote_catalog_item_to_public` (private → public) has no UI.** The
  function exists in `schema.sql`; nothing in the app calls it.
- **PriceCharting "uncertain" review piles.** `pricecharting-catalog-match.mjs`
  never auto-excludes partial-title matches; they were left for a human
  (as of the 2026-09-18 run: NES 15, Atari 2600 21, SNES 39, Genesis 56, Game
  Boy 23, N64 53, PlayStation 38, Dreamcast 11, GameCube 80, PS2 27). The script
  also treats transient HTTP 500s as "not found" — add a retry-on-500 before
  running it again.
- **Reconcile PriceCharting's region signal with IGDB's `regions`.**
  `pricecharting-region-check.mjs` is report-only and was only smoke-tested on
  3 NES items; a real per-platform pass, then a *reviewed* reconciliation
  against the now-live IGDB regions, hasn't been done.
- **MobyGames as a second catalog-metadata source — not started, flagged
  2026-09-18** alongside the region-switch work above. A purpose-built,
  well-regarded release-tracking database with its own API; would need a
  new account/API key (the user's own, same pattern as IGDB/PriceCharting)
  and new integration code (`api/build/ingest/mobygames.mjs`-shaped, not
  started). Deferred in favor of the PriceCharting cross-check above, which
  reuses infrastructure already built and paid for this session.
- Revisit the `GeometryReader` breakdown bar if the `_NSDetectedLayoutRecursion`
  log ever turns into visible jank.
- **RetroGameCollector leftovers.** 16 genuinely ambiguous titles were left
  unmatched, and the ~370 RGC items on platforms unsupported at the time
  (handhelds, Xbox, post-PS2 PlayStation, Switch, plus the then-unbuilt 9) were
  never imported. Some of those platforms now exist (ColecoVision, Intellivision,
  Master System, TurboGrafx-16, Neo Geo, Saturn, 3DO, CD-i, Jaguar) — the RGC
  export CSV lived in a session scratchpad, so it likely needs a re-scrape.

## Multi-user / sync

- **Photos.** `CollectionItem.photoData` still isn't synced — needs the Storage
  bucket upload (`collection-photos`, already created by `schema.sql`, path
  `<user_id>/<exportID>/<n>.jpg`) wired into `SupabaseCollectionSyncEngine` or
  a sibling type. Every other field syncs without it.
- Companion **website** on `retrostacks.com` — same schema, Supabase JS client;
  read-only mirror first, then editing.
- Prune old tombstones after a confirmed successful sync.

## Platform & polish

- iPad: a proper 3-column layout for the collection drill-down.

## Accessibility

Ratchet baselines today (`NavigationTests.swift`): Dashboard 11 · SystemGamesList
52 · CollectionSection 28 · CatalogSection 11 · AddToCollectionFlow 10 ·
SidebarView 4. Lower a screen's baseline when you fix a real finding on it.
Full history of what's been investigated: FEATURES.md → Accessibility.

- **Phase 5 — reading order & a real-device VoiceOver pass.** Not done. Until a
  screen has had a device VoiceOver pass it isn't "done", whatever the audit says.
- **Muted-text contrast.** Most remaining findings are `.secondary` caption
  text. `MutedTextStyle.current` is `.subtle` on purpose (user's call); flip to
  `.compliant` in one place if that decision changes (re-verify the dark-mode
  value first — it's an approximation).
- **Uninvestigated single-row outliers** — Nintendo GameCube (CollectionSection)
  and Sega Dreamcast (AddToCollectionFlow) hard-fail contrast while sibling rows
  don't; and `BreakdownBar`'s contrast findings were investigated and left.
- **`SidebarViewAccessibilityAuditTests` only means something on a
  regular-width destination** (iPad); on iPhone it fails by design because
  `SidebarView` is never mounted. Other screens' audits on iPad also see the
  sidebar alongside the detail pane — filtering by `sidebar.*` identifiers is a
  known gap.

## Testing & tooling

- **`Scripts/leak-check.sh` was written 2026-09-12 and never confirmed
  end-to-end.** The pipeline (signed build → `-uiTesting` launch → `xctrace`
  Leaks attach → `AppWalkthroughTests` → parse) is designed; Phase 3 — make a
  non-empty Leaks table a hard failure — and widening the walkthrough to item
  detail/edit sheets are still open. macOS-hosted UI tests need an interactive
  login session; run them from a real Terminal.
- **Test coverage as a signal, not a target**: Xcode's built-in code coverage
  report (`xcodebuild test -enableCodeCoverage YES`) would show which files
  have zero test coverage at a glance — useful for spotting exactly the kind
  of file (`SupabaseSessionStore`, `SupabaseCollectionRow`) that turned out to
  hide a real bug specifically *because* nothing exercised it yet, without
  chasing an arbitrary coverage percentage.
- **Run `xcodebuild analyze` before a release.** Clean (zero findings) on
  2026-09-18; cheap to repeat, not worth a standing CI step.

## Performance (low priority — main lag fixed 2026-09-19)

Fixed and measured; see FEATURES.md → "Sidebar-switch lag". Remaining ideas:

- First visit after launch still pays ~1-2s for summaries (faults every catalog item per owned platform). Cheaper: SQL `fetchCount` per platform/kind instead of loading items; or warm the cache at launch.
- `DashboardView` `CollectionStatsBuilder.build` still runs on main (fast enough now).
- `CollectionSection.flatItems` `estimatedValue` sort on All Games.
- Opening a platform / Catalog search+filter still uses the background filter over the full catalog fetch; could push predicates into the fetch.
- Catalog no longer live-refreshes on sync while a filtered list is open (updates on next filter change).
- `RootView` destructive `switch` loses view identity on every sidebar switch (keep-alive attempt broke the accessibility audit).
- Debug builds are much slower than Release for SwiftData getters — measure a Release build before chasing more.
