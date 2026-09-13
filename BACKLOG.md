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
- ~~**Barcode scan to add**~~ — implemented 2026-09-13, once the user added
  `NSCameraUsageDescription`: `BarcodeScannerView.swift`
  (`DataScannerViewController` wrapped for SwiftUI, `#if os(iOS)` — VisionKit
  has no macOS equivalent), reachable via a toolbar button in
  `AddToCollectionFlow`. Scans EAN-13/EAN-8/UPC-E/Code-128, looks the payload
  up against `CatalogItem.upc`, adds the match the same simple way every
  other row in that sheet does (consistent with the rest of that flow, no new
  default-value inconsistency). Guards on `DataScannerViewController
  .isSupported`/`.isAvailable` with a real fallback message instead of
  crashing when unsupported. **Not verified working** — the Simulator
  reports `isSupported == false` (no camera), so this is build-verified and
  code-reviewed against Apple's documented API only; needs a real device
  test, which is on the user.
- Multiple copies / variant handling surfaced in the UI (model already supports it).
- ~~**CSV export**~~ — done: `CollectionCSV` + "Export as CSV…" in the Backup menu.
- Per-item **price sparkline** + collection **value-over-time chart** — both need
  the feed to carry price history / periodic snapshots.

## Data feed & backend

- **Disc-system catalogs** (PS1 / PS2 / Dreamcast / GameCube) —
  `api/build/ingest/igdb.mjs` is written and handles them; blocked only on `IGDB_CLIENT_ID` /
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

**Found and fixed 2026-09-13 — two real bugs, not cosmetic:**
- **`DashboardView` never rendered under XCUITest hosting on macOS.**
  `AccountService.init()` did a blocking `SecItemCopyMatching` inline, and
  `DashboardView` reads `AccountService.shared` from a `@State` initializer
  (runs synchronously on the main thread during first render). Found by
  pulling the accessibility-hierarchy dump of 4 failing UI tests via
  `xcresulttool` — it showed only the macOS menu bar, no app window at all.
  Fixed: the Keychain restore now happens in a `Task` kicked off from `init()`
  instead of inline.
- **`SupabaseSessionStore.save()` followed by `.load()` returned nil —
  Keychain persistence was completely broken**, and `SupabaseCollectionRow`
  (the actual sync wire format) had the identical bug, meaning `pull()` would
  have thrown on every real server response (`user_id` is `NOT NULL`, present
  on every row). Root cause: `JSONEncoder`/`Decoder.supabase`'s
  `.convertToSnakeCase`/`.convertFromSnakeCase` is asymmetric for
  acronym-cased fields — encoding `userID` → `"user_id"` is correct, but
  decoding `"user_id"` back only naively capitalizes each segment, producing
  `userId` (lowercase d) — a `keyNotFound` that a `try?` was silently
  swallowing. Fixed with explicit `CodingKeys` + a new
  `JSONEncoder`/`Decoder.exactKeys` (iso8601 dates, no key-conversion
  strategy — deliberately never paired with the snake_case strategy, which
  would fight it). `JSONEncoder`/`Decoder.supabase` stays as-is for GoTrue's
  own auth responses (no acronym fields there). Caught by actually writing
  the regression tests for the first bug (`AccountServiceTests`) — the
  round-trip test failed immediately, for a completely different reason than
  expected. New: `SupabaseCollectionRowTests` decodes a realistic PostgREST
  payload directly, since `SyncCoordinatorTests`' fake engine never exercises
  the real wire format.
- **Every non-2xx HTTP response and non-`errSecSuccess` Keychain status now
  gets logged** via `Services/AppLog.swift` (`os.Logger`, subsystem
  `com.levidahlstrom.RetroStacks`) — `RemoteCatalogRepository`,
  `SupabaseAuthClient`, `SupabaseCollectionSyncEngine`, and
  `SupabaseSessionStore` all had failure paths that either swallowed the
  status entirely or only surfaced a message the user might dismiss without
  it going anywhere durable. This is the standing rule going forward for any
  new API/Keychain call, not just these four.

**Not done yet:**
- **Photos.** `CollectionItem.photoData` still isn't synced — needs the
  Storage bucket upload (`collection-photos`, already created by `schema.sql`,
  path `<user_id>/<exportID>/<n>.jpg`) wired into `SupabaseCollectionSyncEngine`
  or a sibling type. Field sync (everything else) works without it, so this
  was left for a follow-up rather than blocking the rest.
- **A live end-to-end test.** Everything above compiles and is real-Keychain-
  and real-wire-format-tested now, but nobody has actually sent an email,
  pasted a real link back, or watched a real row land in the
  `collection_items` table yet — see `supabase/README.md`'s original note
  about wanting a real round trip before this touches anyone's collection.
  First real sign-in attempt should happen with the user watching, in case
  GoTrue's actual link format or `/verify` response shape differs from what
  the REST docs describe.
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

**Extended 2026-09-13** to the remaining thumbnail-bearing views:
`CatalogPosterCard` (Browse Catalog grid), `CollectionTable` (macOS table
row), and the detail-view headers (`CollectionItemDetailView`,
`CatalogItemDetailView`, `AboutSystemCard`, `QuickAddSheet`) — same
`.accessibilityHidden(true)` treatment for decorative thumbnails, plus
`CatalogPosterCard`'s ownership badge and card grouping brought in line with
the row components. A target-wide sweep for icon-only `Button`/`Menu`
controls with no `.accessibilityLabel` now comes back completely empty.

**Phase 4 (contrast) — done with real numbers, not guesses, 2026-09-13.**
Got `xcodebuild test` working reliably on the iOS Simulator destination for
`RetroStacksUITests` (macOS-hosted UI tests still need the user's own
interactive session — see "Automated leak testing" below), which unlocked
both a real `performAccessibilityAudit()` run *and* hand-computing WCAG
contrast from actual sampled/known sRGB values:

- **`.yellow`** (`StatusBadge`'s wishlist case: text+icon on its own
  `opacity(0.16)` wash) measured **~1.4:1 in light mode** — badly under the
  3:1 UI-component floor, let alone 4.5:1 for text. Dark mode was already
  fine (~6.1:1). Confirmed by hand: sampled the app's real background pixel
  color from a live screenshot, took systemYellow's documented sRGB values,
  composited them the same way the badge does, ran the actual WCAG
  relative-luminance formula.
- Re-ran `performAccessibilityAudit()` on Dashboard with the *OS's own* audit
  (not hand-math) and got 13 real findings, all with element identifiers +
  `.detailedDescription` (not just the near-useless `.compactDescription`).
  Confirmed `.green` has the identical light-mode failure shape (StatTile's
  "+$472 vs. invested" footnote), and 2 `StatTile` texts risk Dynamic-Type
  clipping (`.lineLimit(1)` with no `.minimumScaleFactor`).
- Fixed: new `AccentGold`/`AccentGreen`/`AccentRed` colorsets (darker in
  light mode, unchanged system color in dark mode — see the comment above
  `Color.accentGold` in `Badges.swift`), swapped into every place
  `.yellow`/`.green`/`.red` carried real semantic meaning (owned/wishlisted/
  gain/loss/complete) as text or icon color, app-wide, not just Dashboard.
  `StatTile`'s clipping risk fixed with `.minimumScaleFactor`.
- **Result: 13 → 10 findings.** Left unresolved on purpose (see
  `AccessibilityAuditTests`'s doc comment for the full reasoning): 3 hard
  "Contrast failed" findings inside `BreakdownBar` that survived switching to
  explicit `.primary` — best-evidenced theory is a saturated bar washing out
  nearby text structurally, not a wrong-color-choice, and needs a real visual
  iteration pass; and 7 "`.secondary` at `.caption` nearly passes" warnings,
  which is the *default look of `.secondary` text everywhere in the app*, not
  a Dashboard bug — a design decision on how muted that should read, not
  something to change unilaterally.

**Phase 6 (the automated gate) — done, as a ratchet.**
`AccessibilityAuditTests.testDashboardAccessibilityAudit` now asserts
`findings.count <= knownFindingBaseline` (10) instead of only logging —
catches any *new* regression immediately without requiring the screen to be
perfectly clean first (which Phase 5 hasn't happened yet). Lower the baseline
as the remaining 10 get fixed for real.

**Phase 5 — reading order & real VoiceOver navigation. Not done.** Simulator
access is authorized (one-time grant, confirmed persistent across sessions),
but the `inspect` action returned "not available right now" every time it was
tried this session (worth retrying — possibly needs the app already running,
or is just flaky in this environment). The `xcresulttool export attachments`
route *does* work reliably now (used it for the Phase 4 audit above) and is a
real, proven substitute — pull each screen's accessibility-hierarchy dump
that way and read through it as a stand-in for a VoiceOver pass. Still do a
real device VoiceOver pass before calling any screen actually done — that
step is a device/OS interaction, not something to substitute away entirely.

**Remaining screens** (same phase order, not yet touched): `AddToCollectionFlow`
(new this session — the barcode scanner and system-first picker haven't had
an accessibility pass yet), `CatalogSection`'s own chrome, and `SidebarView`
(already has identifiers; check for icon-only spots once it grows
badges/actions). And the audit above only ever exercised Dashboard — the
same real-audit technique (not hand-guessing) should extend to
`SystemGamesList`, `CollectionSection`, and `CatalogSection` next.

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

**Resolved 2026-09-13, sort of: `xcodebuild test -destination 'platform=macOS'`
needs an interactive, unlocked login session to run at all.** Every attempt
from this automated/headless session hung indefinitely at "Testing started
completed" (0% CPU, no test host ever appeared) — but the user ran the exact
same command from their own Terminal and it completed in 86s. XCUITest on
macOS needs to inject synthetic events into a real windowed host app, which
needs an actual WindowServer session able to receive them; a background shell
with no one logged in and looking at the screen apparently can't provide
that (same underlying class of constraint as the Screen Recording/
Accessibility/Developer Tools permissions from earlier this project — but
this one isn't a one-time grant, it's "someone has to actually run it"). So:
**this only ever needs to be run by the user, in an interactive session** —
not a blocker to fix, just a fact about this tool. That run also surfaced 4
real UI test failures, traced to a genuine bug (see "Multi-user" section
above) and fixed.

**Update, same day:** `-destination 'platform=iOS Simulator,...'` *does* work
reliably from this automated session for `RetroStacksUITests` (used it for
the whole Phase 4 accessibility-audit push above) — no interactive-session
requirement there, since it's driving a simulator process, not injecting
into a real macOS window. The one real rough edge: `CoreSimulatorService`
itself crashed mid-run twice this session ("(ipc/mig) server died"),
unrelated to any of this project's code — `killall -9
com.apple.CoreSimulator.CoreSimulatorService` (it restarts itself) and retry
if a run fails with that specific error.

**Phase 3 — assert, don't just report.** Once the above is unblocked and the
walkthrough's coverage is widened, this becomes a real regression gate
(matching `CLAUDE.md`'s Testing Discipline): non-empty Leaks table = script
exits non-zero. Run it locally before a release, or on demand — real
Instruments profiling has genuine wall-clock cost (this session's manual runs
took 45–90s of recording plus build/export time), so it's a deliberate
"run me" tool, not a be-run-on-every-commit unit test.

## UX tap-friction audit (2026-09-13) — mostly implemented

Full audit: every core action from Dashboard, `CollectionSection`,
`SystemGamesList`, `QuickAddSheet`, `CollectionItemEditView`/`DetailView`,
catalog browsing, sign-in, sync, export/import — counted taps end to end.
Most core actions were already at or under 2 taps (adding an owned/wishlist
item from any of the three entry points, bulk-add). Findings and their fate:

- ~~**Changing condition or completeness on an existing item was 4 taps**~~
  — done: `CollectionItemDetailView`'s toolbar menu (renamed "Quick Edit")
  now embeds Condition and Completeness `Picker`s alongside the existing
  Status one, each auto-saving via `.onChange` — 2 taps, no Edit/Save round
  trip. Full edit form still there for bulk/rare fields.
- ~~**Deleting an item from the detail view was 3 taps**~~ — done: Delete is
  now its own toolbar button instead of nested in the menu; same
  confirmation dialog, one fewer tap to reach it.
- ~~**Sign In cost 2 "reach the sheet" taps**~~ — done: dedicated toolbar
  entry point (`person.crop.circle`, becomes `.fill` + a menu once signed
  in) instead of living inside "View Options."
- ~~**Import/export success ended on a blocking OK-only alert**~~ — done:
  new `Views/Components/Toast.swift`, an auto-dismissing bottom banner.
  Real failures still get a blocking `alert`.
- ~~**Swipe-to-remove had no confirmation, unlike the detail view's menu**~~
  — done, via the same `Toast` with an "Undo" action instead of a blocking
  confirmation (which would've defeated the point of a fast swipe) —
  `CollectionSection`'s flat list and `SystemGamesList`'s drill-down both
  show "Removed — Undo" now. Not touched: `SystemCatalogTile`'s macOS
  right-click Remove (deliberate secondary action, not an accidental-swipe
  risk the same way).
- ~~**Hidden on iOS: the wishlist star only showed once already
  wishlisted**~~ — done: persistent on iOS now; still hover-gated on macOS
  (a real declutter there, not the only way in).
- ~~**Inconsistent defaults**~~ — decided 2026-09-13 (user's call: always show
  the picker): `CatalogItemDetailView` and `AddToCollectionFlow` (all three of
  its entry points — platform picker, flat search, barcode scanner, since
  they all funnel through one `add(_:)`) now route owned adds through
  `QuickAddSheet` too, matching `SystemGamesList`. Wishlist adds still skip
  it everywhere (completeness/condition aren't meaningful for a wishlist
  entry) — that part was never inconsistent.

## Catalog browsing at scale — done

**Implemented 2026-09-13.** Both catalog-browsing entry points
(`AddToCollectionFlow`'s picker sheet, `CatalogSection`'s standalone Browse
Catalog tab) now default to a system-first list — pick a platform, then
search/filter within just that platform's titles — instead of one flat list
of everything (~3,600 entries and growing). Typing into the search field is
still a full-catalog, cross-platform escape hatch for "I know exactly what
I'm looking for." `CatalogSection` reuses its existing `platformSlugFilter`
for this (picking a platform just sets the same field the toolbar's Platform
picker already used), so every existing filter/sort/ownership combination
keeps working unchanged once a platform is chosen; a new "All Systems"
toolbar button clears just that field. `CatalogPlatformRow` (icon, name,
entry count) is shared between both entry points.

Not done: hasn't been visually click-through tested (macOS UI-automation
tooling was unreliable this session — see the `xcodebuild test` note
elsewhere in this doc), only build-verified + code-reviewed against the same
patterns already proven elsewhere (`CollectionSection`'s system-first list,
`SystemGamesList`'s per-platform search). Worth a look next time the app is
open.

## Code health & error analytics

Raised 2026-09-13, prompted by the `userID`/snake_case bug above slipping
through undetected until a regression test happened to hit it. Concrete,
sized-to-a-solo-project recommendations (no team, no budget for heavyweight
tooling):

- **The logging rule is now standing policy, not a one-off**: every non-2xx
  API response and non-success Keychain/system-API status gets logged via
  `AppLog` (`Services/AppLog.swift`), even when it's also surfaced to the UI
  or rethrown. Apply this to any *new* external call as it's written, not
  just the four fixed this session.
- **`try?` is a code smell worth grepping for periodically** — it was the
  single line that hid the `userID` bug for as long as it did. A `try?` is
  legitimate when "this specific failure is fine to ignore" is a real,
  intentional decision (documented inline); it's a bug waiting to be found
  when it's really "I didn't want to handle this error." Worth a occasional
  `grep -rn "try?" apple/RetroStacks` pass to confirm each one is still the
  former.
- **Xcode's own static analyzer** (Product → Analyze, or `xcodebuild analyze`)
  catches a real class of bugs (retain cycles, unreachable code, misused
  APIs) for zero setup cost — not currently run anywhere in this project's
  workflow. Cheap to add as an occasional manual check before a release, or
  wired into `Scripts/` alongside `leak-check.sh`.
- ~~**SwiftLint**~~ — done 2026-09-13: `.swiftlint.yml` (repo root) +
  `Scripts/lint.sh` (`--fix` for auto-fixable violations, then report). Not
  wired into an Xcode Build Phase or SPM plugin — both would mean editing
  `project.pbxproj`/package deps, off-limits per `CLAUDE.md`'s guardrails —
  so it's a manual/CI step for now. First real run: 120 violations, mostly
  `identifier_name` noise on this codebase's short-closure-param idiom
  (`{ m in ... }`) — tuned out via `min_length: 0`. `--fix` handled the
  mechanical ones (trailing commas, redundant optional init) down to 60.
  Every remaining `force_try`/`force_unwrapping` was reviewed by hand:
  `#Preview`-only force-tries and safe-by-construction literals
  (`URL(string: "https://...")!`, `Calendar.date(byAdding:)!` on a valid
  date) got an inline `// swiftlint:disable:next` with a one-line reason;
  the real ones — `URLComponents`/`.url` construction in
  `SupabaseAuthClient`, `SupabaseCollectionSyncEngine`, and
  `PriceChartingProvider` — were converted to `guard let ... else { throw }`
  instead of just silencing the rule. Two 3-member tuples
  (`DashboardView`'s `BreakdownRow`, `CollectionArchive.restore`'s
  `RestoreSummary`) got named structs. Left alone, deliberately not
  refactored blind under a lint pass: `cyclomatic_complexity` on
  `CatalogBrowseViewModel.applyFilters`/`CatalogSeedStore`'s importer/
  `PriceChartingProvider.priceReport` (the last grew from 10→12 by adding
  the `guard let` above — an acceptable tradeoff for not crashing on a
  malformed URL), `function_body_length` on `CatalogSyncService`, and
  `file_length`/`type_body_length` on `SystemGamesList` (851 lines, grown
  from the `PlatformDetailView` merge noted above — a real split candidate,
  just not attempted blind under a lint pass). 6 warnings remain, 0
  errors; `knownFindingBaseline`-style tracking isn't set up for lint the
  way it is for the accessibility audit, so these are just visible in
  `Scripts/lint.sh` output going forward.
- **Test coverage as a signal, not a target**: Xcode's built-in code coverage
  report (`xcodebuild test -enableCodeCoverage YES`) would show which files
  have zero test coverage at a glance — useful for spotting exactly the kind
  of file (`SupabaseSessionStore`, `SupabaseCollectionRow`) that turned out to
  hide a real bug specifically *because* nothing exercised it yet, without
  chasing an arbitrary coverage percentage.
- **What's deliberately not recommended**: a crash-reporting/analytics SDK
  (Sentry, Firebase Crashlytics, etc.) — real value once this has real users,
  but for a solo pre-release project it's a dependency and a privacy surface
  for no current payoff. `AppStatusCenter` (user-facing) + `AppLog` (developer
  log) already covers "know when something failed" at the current scale;
  revisit if/when this ships to other people.

## Platform & polish

- ~~App icon~~ — locked in 2026-09-13: NES/Genesis/N64-esque console trio,
  blue/red palette, collector star badge. Placeholder-quality, not final —
  user's own words: "we'll come up with something better later." Revisit
  when there's appetite for a real design pass; not urgent, just no longer a
  blank icon.
- ~~Surface background API failures in the UI~~ — done: `AppStatusCenter` +
  corner `AppStatusBadge`. Wired for catalog sync + price refresh + collection
  sync (`SyncCoordinator` reports/clears `.collectionSync`, same pattern).
- iPad: a proper 3-column layout for the collection drill-down.
- EU / JP region switch (`Region` already modeled).
- Revisit the `GeometryReader` breakdown bar if the `_NSDetectedLayoutRecursion`
  log ever turns into visible jank.
