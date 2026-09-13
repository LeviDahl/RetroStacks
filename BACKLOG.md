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

**Wired up 2026-09-12** — the user's Supabase project went live and handed back
the URL + anon key (`Services/Sync/SupabaseConfig.swift`). Done:

- `SupabaseAuthClient` (`Services/Sync/SupabaseAuthClient.swift`) — GoTrue over
  plain REST, no SDK (avoids an SPM package dependency, which would mean
  editing `project.pbxproj` — off-limits per `CLAUDE.md`). Email magic-link,
  but **the user pastes the link back** instead of the app catching a deep-link
  callback (`completeSignIn(pastedLink:)` parses `token`/`token_hash` + `type`
  straight out of the link's query string and calls `/verify` directly) — that
  needed no custom URL scheme, so no Xcode target changes either. `SignInSheet`
  (`Views/Account/SignInSheet.swift`) is the UI, reachable from the Dashboard's
  account row.
- `SupabaseSession` + `SupabaseSessionStore` (Keychain-backed, not
  `UserDefaults` — access/refresh tokens shouldn't sit in a plist).
  `AccountService` now does real sign-in/out and token refresh
  (`validAccessToken()`), restoring the session from Keychain at launch.
- `SupabaseCollectionSyncEngine` implements `CollectionSyncEngine` against
  `public.collection_items` (PostgREST upsert with `Prefer:
  resolution=merge-duplicates`) — `Sync.engine` now points at it instead of
  `DisabledSyncEngine`.
- `SyncCoordinator` (`Services/Sync/SyncCoordinator.swift`) — pull, resolve
  last-write-wins by `updatedAt`, push what's still locally dirty, settle
  authoritative timestamps back. Runs on app launch (`.task` in
  `RetroStacksApp`, alongside `CatalogSyncService`, both no-ops while signed
  out) and right after sign-in; a manual "Sync collection now" sits in the
  Dashboard's menu next to the existing catalog one. Failures report to
  `AppStatusCenter.shared(.collectionSync)`, same corner badge as everything
  else. Covered by `RetroStacksTests/SyncCoordinatorTests.swift` (conflict
  resolution, first-sync, failure path — fake engine, no network) and
  `SupabaseAuthClientTests.swift` (link-parsing).
- `CollectionArchive.Entry.init(item:)` / `.apply(to:catalogBySlug:)` — the
  field mapping used to live inline in `CollectionArchive.make`/`.restore`
  only; extracted so the sync engine's row mapping and the local JSON backup
  share one place to get it right. `CollectionArchiveTests.swift` locks the
  round trip down.

**Not done yet:**
- **Photos.** `CollectionItem.photoData` still isn't synced — needs the
  Storage bucket upload (`collection-photos`, already created by `schema.sql`,
  path `<user_id>/<exportID>/<n>.jpg`) wired into `SupabaseCollectionSyncEngine`
  or a sibling type. Field sync (everything else) works without it, so this
  was left for a follow-up rather than blocking the rest.
- **A live end-to-end test.** Everything above compiles and is unit-tested
  against a fake engine, but nobody has actually sent an email, pasted a real
  link back, or watched a real row land in the `collection_items` table yet —
  see `supabase/README.md`'s original note about wanting a real round trip
  before this touches anyone's collection. First real sign-in attempt should
  happen with the user watching, in case GoTrue's actual link format or
  `/verify` response shape differs from what the REST docs describe.
- Companion **website** on `retrostacks.com` — same schema, Supabase JS client;
  read-only mirror first, then editing.
- Prune old tombstones after a confirmed successful sync.

## Accessibility — path to full VoiceOver compliance

**Phases 1–3 done 2026-09-12** across the highest-traffic screens (Dashboard,
`SystemGamesList`/`SystemCatalogTile`, `CollectionSection`/`CollectionItemRow`,
`CatalogItemRow`, `SystemCollectionRow`, `CollectionItemEditView`,
`AppStatusBadge`, `StatTile`, `SignInSheet`). What landed:

- **Phase 1 (identifiers)** — `AccessibilityID.swift` grew a `Sidebar` and
  `Account` namespace alongside the original `Dashboard` one, all following the
  same "keyed by durable model identity, never array position" rule.
- **Phase 2 (labels/hints/grouping)** — every icon-only `Button` in `Views/`
  now has a real `.accessibilityLabel` (a `grep` sweep for `Button { Image(
  systemName:...) }` with no label, re-run until it came back empty — it did,
  see the sweep in git history for the exact pattern). Composite rows
  (`CollectionItemRow`, `CatalogItemRow`, `SystemCollectionRow`,
  `PlatformCatalogRow`'s trailing value cluster) now use
  `.accessibilityElement(children: .combine)` so VoiceOver reads one sentence
  per row; their `ItemThumbnail`s are `.accessibilityHidden(true)` (decorative
  — the title text beside them says the same thing); status icons
  (owned/wishlisted checkmarks and stars) got explicit labels instead of
  leaking their SF Symbol name. Along the way, found and fixed a real bug:
  `ConditionLabel(compact: true)` (used in every `CollectionItemRow`) rendered
  as a bare colored `Circle()` with **no accessible text at all** — condition
  was completely invisible to VoiceOver on every collection row. Now has an
  explicit `.accessibilityLabel`.
- **Phase 3 (Dynamic Type)** — the one concretely-named risk spot,
  `DashboardView`'s big collection-count number
  (`.font(.system(size: 46, ...))`, a literal point size that doesn't scale
  with Dynamic Type at all) now uses `@ScaledMetric(relativeTo: .largeTitle)`
  so it still scales up at larger accessibility text sizes. Audited the rest of
  the `.font(.system(size:))` call sites in `Views/` — the other two are
  decorative glyphs sized proportionally to a fixed-size container
  (`AboutSystemCard`'s fallback console icon, `ItemThumbnail`'s placeholder),
  which is the *correct* thing to leave fixed (scaling them would overflow
  their box) — not a gap.

**Phase 4 (contrast) — investigated, lower risk than this doc originally
guessed.** The original note here assumed `PlatformPalette` colors were used
as text-on-fill; checked every call site and that's not actually how they're
used — `BreakdownBar`'s colored capsule is a plain decorative fill with no text
drawn on top of it (the value/count labels sit beside it against the normal
background), and `SystemCollectionRow`'s accent is a thin bar + a
`ProgressView` tint, also no text-on-color. `PlatformPalette.colors` are also
all Apple system semantic colors (`.red`, `.teal`, …), not custom hex, which
Apple already tunes per-appearance for legibility. Real remaining question:
`Badges.swift`'s `StatusBadge`/`CompletenessBadge` pattern (saturated color
text on a `color.opacity(0.16-0.18)` wash of the *same* hue) — probably fine,
but `.yellow` (the wishlist `StatusBadge`) is the one classic problem color for
contrast and is worth an actual look with Xcode's contrast checker or
`Accessibility Inspector.app` rather than guessing further from code.

**Not done — genuinely needs a live VoiceOver pass, not more code-reading:**
attempted to verify Phases 2–3 by actually inspecting the accessibility tree
(the iOS Simulator tool's `inspect` action, a real stand-in for VoiceOver —
see `Phase 5` below) but the simulator device isn't yet authorized for Claude
to attach to in this environment ("the user has not granted Claude access to
iPhone 17 Pro"); a macOS-hosted `xcodebuild test` run (which is how
`AccessibilityAuditTests`/`NavigationTests` actually execute) currently hangs
indefinitely in this environment too (see "Automated leak testing" section
below — same root cause, `testmanagerd` never completing its handshake for a
macOS test host). Tests **do** run and pass on the iOS Simulator destination
(`-destination 'platform=iOS Simulator,...'`), so the code itself is verified
by that path, but nobody has actually watched a real device/simulator
announce these screens with VoiceOver toggled on yet.

**Phase 5 — reading order & real VoiceOver navigation.** Once the Simulator
authorization above is granted (one-time: attach the simulator panel and click
"Let Claude use it"), pull each screen's accessibility-hierarchy dump via
`inspect` (or `xcrun xcresulttool export attachments ... --test-id` off a UI
test run, the technique already proven this session for `NavigationTests`) and
read through it as a stand-in for a VoiceOver pass; still do a real device
VoiceOver pass before calling any screen actually done — that step is a
device/OS interaction, not something I can substitute for.

**Phase 6 — the automated gate.** `AccessibilityAuditTests.testDashboardAccessibilityAudit`
still logs+attaches findings but never fails (see `CLAUDE.md`) — deliberately
left alone this pass since it needs the Phase 5 live pass first to know what
"clean" actually looks like for a screen; tightening it now would either be a
guess or lock in whatever the audit happens to currently report.

**Remaining screens** (same phase order, not yet touched): `CatalogSection` /
`CatalogItemRow` polish, detail/edit views (`CollectionItemDetailView`,
`CatalogItemDetailView`, `QuickAddSheet`, `AddToCollectionFlow`), and
`SidebarView` (already has identifiers from earlier this session; check for
any remaining icon-only spots once the sidebar grows badges/actions).

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

**Phase 1 — `Scripts/leak-check.sh`. Written 2026-09-12, not yet run
end-to-end** (see the blocker below). Wires the above into one script: build
(signed) → `open ... --args -uiTesting` → capture PID → `xctrace record
--instrument Leaks --attach <pid> --no-prompt` in the background → run an
XCUITest "walkthrough" class against the running instance → SIGINT the
recorder → `xctrace export` the Leaks detail table → parse for `<row>`
elements → exit non-zero (and print the leaked objects + stacks) if any exist.
Results land in `leak-results/<timestamp>/` (gitignored).

**Phase 2 — `RetroStacksUITests/AppWalkthroughTests.swift`. Written
2026-09-12.** Attaches (doesn't launch) and visits Dashboard → Owned Items →
My Collection → toggle grouping → a system screen (scope picker + About
disclosure) → Wishlist → Catalog → back to Dashboard, **twice** — a single
visit often won't surface a retain cycle, visiting/leaving and confirming
nothing accumulates on the second pass is the actual test. Builds cleanly.
Narrower than the ideal coverage described in earlier drafts of this plan
(doesn't yet touch item detail/edit sheets) — worth widening once the
run-it-at-all blocker below is cleared and there's a real trace to check
widening against.

**Currently blocked: `xcodebuild test` hangs indefinitely for this project on
macOS in this environment**, discovered while adding unit tests for the
Supabase sync work above. Every macOS-destination `xcodebuild ... test` (or
`test-without-building`) invocation stalls forever at "Testing started
completed" — 0% CPU, no test host process ever appears, reproducible across
multiple clean attempts, survives killing a stale `testmanagerd`, and is
identical whether or not the invocation was just rebuilt. The **same test
target runs and passes cleanly** on an iOS Simulator destination
(`-destination 'platform=iOS Simulator,...'`) — so this isn't a code problem,
it's specific to macOS-hosted test execution (`RetroStacksTests`'/
`RetroStacksUITests`' `TEST_HOST` launches the real signed `RetroStacks.app`
as the actual test host on macOS) in this particular environment. Likely a
permissions/session gap for whatever `testmanagerd` needs to inject into and
control a macOS host app — possibly adjacent to the Screen Recording /
Accessibility / Developer Tools permissions this session already had to sort
out for `xctrace` and window-scoped screenshots earlier. **Needs the user**:
either run `Scripts/leak-check.sh` (or plain `xcodebuild test -destination
'platform=macOS'`) once locally in a normal Terminal/Xcode session to confirm
it's environment-specific and not a real regression, or point at whatever
permission macOS wants granted for automated macOS UI testing.

**Phase 3 — assert, don't just report.** Once the above is unblocked and the
walkthrough's coverage is widened, this becomes a real regression gate
(matching `CLAUDE.md`'s Testing Discipline): non-empty Leaks table = script
exits non-zero. Run it locally before a release, or on demand — real
Instruments profiling has genuine wall-clock cost (this session's manual runs
took 45–90s of recording plus build/export time), so it's a deliberate
"run me" tool, not a be-run-on-every-commit unit test.

## Platform & polish

- ~~Surface background API failures in the UI~~ — done: `AppStatusCenter` +
  corner `AppStatusBadge`. Wired for catalog sync + price refresh + collection
  sync (`SyncCoordinator` reports/clears `.collectionSync`, same pattern).
- iPad: a proper 3-column layout for the collection drill-down.
- EU / JP region switch (`Region` already modeled).
- Revisit the `GeometryReader` breakdown bar if the `_NSDetectedLayoutRecursion`
  log ever turns into visible jank.
