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

## Accessibility — path to full VoiceOver compliance

Near-zero today: 5 accessibility annotations in the whole app (2 identifiers
bootstrapped 2026-09-12 for `NavigationTests`, the A–Z scrubber's label, the
status badge icon's label, one more), and ~19 view files with interactive
`Button`s that have no VoiceOver label — they lean on `.help()`, a macOS
mouse-hover tooltip that VoiceOver never reads. Two independent reasons to
close this gap: real VoiceOver support, and reliable automation (both my own
testing and `RetroStacksUITests`) — discovered the hard way when `System
Events` and then `app.staticTexts[...]` both had nothing queryable to act on.
First real audit (`AccessibilityAuditTests`, Dashboard only) already found 9
issues. This is the full path; each phase is independently shippable and
should land screen-by-screen (per `CLAUDE.md`'s Testing Discipline), not as
one sweep — the identifier work only (phase 1) is already started.

**Phase 1 — identifiers (automation-focused, in progress).** `App/AccessibilityID.swift`,
namespaced per `Views/<Feature>/` folder, two shapes: static ids for one-off
chrome (`AccessibilityID.Dashboard.ownedItemsTile`), keyed ids for repeated
content built from the model's own durable identity — `platform.slug`,
`catalogItem.slug`, `item.resolvedExportID` — **never** array position, so a
resort/refilter never changes what a row is addressed as. Currently covers 2
Dashboard elements; extend to every interactive element per screen as phases
2+ touch that screen (no separate pass — add the identifier while adding the
label, same edit).

**Phase 2 — VoiceOver labels, hints, and element grouping.** The mechanical
"missing description" fixes, screen by screen:
- Every icon-only control (`Button` wrapping just an `Image(systemName:)`,
  found via `grep -rln "labelStyle(.iconOnly)" Views App`) gets a real
  `.accessibilityLabel` — what it *is* — and `.accessibilityHint` where the
  result of tapping isn't obvious from the label alone (e.g. the sort/kind
  menu trigger, the wishlist star toggle).
- Every composite row/tile (`PlatformCatalogRow`, `SystemCatalogTile`,
  `CollectionItemRow`, `CatalogItemRow`, `StatTile`, `SystemCollectionRow`) —
  currently several separate `Text`/`Image` children — gets
  `.accessibilityElement(children: .combine)` (or `.ignore` + one explicit
  `.accessibilityLabel`) so VoiceOver reads one coherent sentence per row
  ("Chrono Trigger, Game, 1995, Square, Complete in Box, $450, Owned") instead
  of announcing each fragment as a separate stop. This is also what determines
  swipe-navigation order — needs checking against visual reading order per row,
  not just "does a label exist."
- Purely decorative images (box art sitting right next to the title text that
  already says the same thing) get `.accessibilityHidden(true)` rather than a
  redundant label — don't over-announce.

**Phase 3 — Dynamic Type.** Verify layout holds at the accessibility text
sizes (AX1–AX5), not just the default size. Known risk spots: `DashboardView`'s
fixed `.font(.system(size: 46, …))` big number, any `.lineLimit`+no
`.minimumScaleFactor` combination on a row that's already tight (the SNES
breakdown-row width fix from earlier this session is exactly this kind of
issue). Test via the Simulator's Settings → Accessibility → Larger Text at
max, or `xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`,
and re-run the screenshot-based visual check per screen.

**Phase 4 — contrast & visual accessibility.** `PlatformPalette`'s per-platform
colors (used as text-on-fill in `BreakdownBar`, badge backgrounds) need a WCAG
AA contrast check against both the light and dark palette — some of the
lighter accent colors are likely borderline against white text at the sizes
used. `performAccessibilityAudit()` (phase 6) catches some of this
automatically; a manual pass with Xcode's contrast checker or
`Accessibility Inspector.app` (already installed with Xcode, GUI-only, can't
drive it myself — genuinely needs the user or a screenshot-based color-sample
check) covers the rest.

**Phase 5 — reading order & real VoiceOver navigation.** Structural audits
(phase 6) can't catch "does swiping through this screen with VoiceOver on
actually make sense" — that needs either a human running VoiceOver on a real
device/Simulator, or me inspecting the accessibility-hierarchy dump (the same
`xcrun xcresulttool export attachments ... --test-id` technique used to debug
`NavigationTests` this session shows the exact tree VoiceOver reads from,
including label/value/trait per element — a real, if indirect, way for me to
verify order and content without literally hearing speech output). Plan: once
phases 2–4 land for a screen, pull that screen's hierarchy dump and read
through it as a stand-in for a VoiceOver pass; do a real device VoiceOver
pass before calling any screen actually done.

**Phase 6 — the automated gate.** `AccessibilityAuditTests.testDashboardAccessibilityAudit`
currently logs+attaches findings but never fails (see `CLAUDE.md`). Once a
screen clears phases 2–4, add a screen-specific audit test for it that
**does** fail on new findings (`XCTAssertTrue(issue.auditType != .sufficientElementDescription`-style
filtering, or just `try app.performAccessibilityAudit()` with no
issue-handler once a screen is genuinely clean) — this is what keeps a screen
from silently regressing once it's fixed, same "regression test at fix time"
discipline as the rest of the suite.

**Suggested order** (highest-traffic first): Dashboard (partially started) →
`SystemGamesList` / `SystemCatalogTile` (the densest screen, most icon-only
controls) → `CollectionSection` / `CollectionItemRow` → `CatalogSection` /
`CatalogItemRow` → detail/edit views (`CollectionItemDetailView`,
`CollectionItemEditView`, `CatalogItemDetailView`, `QuickAddSheet`,
`AddToCollectionFlow`) → chrome (`SidebarView`, `AppStatusBadge`).

## Automated leak testing — exhaustive, unattended

2026-09-12's manual Leaks pass (attached `xctrace`, user clicking around)
proved the mechanism but needed a human driving the app and only covered
whatever got clicked in ~45s. The goal: the same Leaks capture, but the
*driving* is done by code, so it's repeatable, covers the whole app on
purpose, and can run without anyone at the keyboard.

**What's already proven working this session** (the hard part — don't
rediscover these):
- The target app must be built with **real project signing** (no
  `CODE_SIGNING_ALLOWED=NO`) — that's what actually gives it the
  `com.apple.security.get-task-allow` entitlement `xctrace --attach` needs.
  Confirmed via `codesign -d --entitlements -`.
- Launch with **`-uiTesting`** so the profiled session isn't dominated by the
  real catalog network sync (unrelated allocation volume, not what we're
  trying to measure) — `RetroStacksApp.isUITesting`.
- Use **`xctrace record --instrument 'Leaks'`**, *not* `--template 'Leaks'` —
  the template bundles the Allocations instrument with full per-allocation
  backtrace logging, which generated 3.75–6.7 GB from ordinary SwiftUI churn
  in under 90 seconds and crashed `xctrace`'s own save step (`NSArchiver`'s
  ~4 GB ceiling) twice before this fix. The bare `Leaks` instrument alone
  produced a clean 16 MB trace.
- Results are queryable headlessly: `xcrun xctrace export --input trace
  --xpath '/trace-toc/run[@number="1"]/data/track[@name="Leaks"]/detail[@name="Leaks"]'
  --output result.xml` — an empty `<trace-query-result/>` means no leaks
  found; a non-empty one lists the leaked objects with allocation backtraces.
  This is a real pass/fail signal a script can parse.
- **XCUITest can drive an already-running process** it didn't launch:
  `XCUIApplication(bundleIdentifier: "com.levidahlstrom.RetroStacks")`
  without calling `.launch()` attaches to whatever instance is already up —
  this is the piece that lets `xctrace --attach <pid>` and an XCUITest
  "walkthrough" both target the *same* process instead of fighting over who
  launches it.

**Phase 1 — `Scripts/leak-check.sh`.** Wire the above into one script:
build (signed) → `open ... --args -uiTesting` → capture PID → `xctrace record
--instrument Leaks --attach <pid> --no-prompt` in the background → run an
XCUITest "walkthrough" class against the running instance → SIGINT the
recorder → `xctrace export` the Leaks detail table → parse for `<row>`
elements → exit non-zero (and print the leaked objects + stacks) if any exist.
Valuable even before phase 2 is done — it's a real, working, rerunnable tool
from day one, just with partial screen coverage until the walkthrough grows.

**Phase 2 — `RetroStacksUITests/AppWalkthroughTests.swift`.** A test class that
attaches (doesn't launch) and systematically visits **every** screen, **more
than once** — a single visit often won't surface a retain cycle, visiting and
leaving 2–3× and confirming nothing accumulates is the real test:
Dashboard → tap into a breakdown row → back → tap Owned Items → My Collection
→ toggle By System/All Games → drill into 2–3 systems → open an item detail →
open the edit sheet, cancel → open it again, change a field, save → back out
→ Wishlist (same shape) → Browse Catalog → open a few item details → back →
repeat the whole loop once more. Needs Phase 1 of the Accessibility path
(identifiers) to exist for whatever it's currently missing — the two efforts
share infrastructure, not just tooling philosophy.

**Phase 3 — assert, don't just report.** Once phase 1+2 are solid, this
becomes a real regression gate (matching `CLAUDE.md`'s Testing Discipline):
non-empty Leaks table = script exits non-zero. Run it locally before a
release, or on demand — real Instruments profiling has genuine wall-clock
cost (this session's runs took 45–90s of recording plus build/export time),
so it's a deliberate "run me" tool, not a be-run-on-every-commit unit test.

## Platform & polish

- ~~Surface background API failures in the UI~~ — done: `AppStatusCenter` +
  corner `AppStatusBadge`. Wired for catalog sync + price refresh; `Supabase*`
  engines should `report(.collectionSync, …)` / `clear` the same way.
- iPad: a proper 3-column layout for the collection drill-down.
- EU / JP region switch (`Region` already modeled).
- Revisit the `GeometryReader` breakdown bar if the `_NSDetectedLayoutRecursion`
  log ever turns into visible jank.
