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

**Extended 2026-09-13** to the remaining thumbnail-bearing views:
`CatalogPosterCard` (Browse Catalog grid), `CollectionTable` (macOS table
row), and the detail-view headers (`CollectionItemDetailView`,
`CatalogItemDetailView`, `AboutSystemCard`, `QuickAddSheet`) — same
`.accessibilityHidden(true)` treatment for decorative thumbnails, plus
`CatalogPosterCard`'s ownership badge and card grouping brought in line with
the row components. A target-wide sweep for icon-only `Button`/`Menu`
controls with no `.accessibilityLabel` now comes back completely empty.

**Not done — genuinely needs a live VoiceOver pass, not more code-reading.**
Simulator access is now authorized (one-time grant, confirmed persistent
across sessions), so the `inspect` action (a real stand-in for VoiceOver —
see Phase 5) is available going forward, though it returned "not available
right now" both times it was tried this session — worth retrying, possibly
just needs the app already running when called. `AccessibilityAuditTests`/
`NavigationTests` (macOS-hosted UI tests) need the user's own interactive
session to run at all (see "Automated leak testing" section — same
constraint, not a bug). Unit-level coverage passes on the iOS Simulator
destination, so the code itself is verified by that path, but nobody has
actually watched a real device/simulator announce these screens with
VoiceOver toggled on yet.

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

**Remaining screens** (same phase order, not yet touched): `AddToCollectionFlow`,
`CatalogSection`'s own chrome (as opposed to `CatalogItemRow`/`CatalogPosterCard`,
both now covered), and `SidebarView` (already has identifiers from earlier
this session; check for any remaining icon-only spots once the sidebar grows
badges/actions).

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

**Phase 3 — assert, don't just report.** Once the above is unblocked and the
walkthrough's coverage is widened, this becomes a real regression gate
(matching `CLAUDE.md`'s Testing Discipline): non-empty Leaks table = script
exits non-zero. Run it locally before a release, or on demand — real
Instruments profiling has genuine wall-clock cost (this session's manual runs
took 45–90s of recording plus build/export time), so it's a deliberate
"run me" tool, not a be-run-on-every-commit unit test.

## UX tap-friction audit (2026-09-13)

Full audit: every core action from Dashboard, `CollectionSection`,
`SystemGamesList`, `QuickAddSheet`, `CollectionItemEditView`/`DetailView`,
catalog browsing, sign-in, sync, export/import — counted taps end to end.
Most core actions are already at or under 2 taps (adding an owned/wishlist
item from any of the three entry points, bulk-add, the `More`-menu status
picker). What's actually over budget, ranked by how much it matters:

- **Changing condition or completeness on an existing item is 4 taps**
  (Edit → tap the field row → tap the value → Save) — the one flagged by the
  user's own example applies here too: `CollectionItemEditView` puts these in
  plain `Form` `Picker`s that push to a separate list. The app already has
  the *right* pattern next door: `CollectionItemDetailView`'s `More` menu
  embeds a `Picker` for Status directly, auto-saving via `.onChange` — 2 taps,
  no Edit/Save round trip. **Fix:** extend that same quick-picker pattern to
  Condition and Completeness in the `More` menu. Takes the common case from 4
  taps to 2 without touching the full edit form (still there for bulk/rare
  fields).
- **Deleting an item from the detail view is 3 taps** (More → Delete → confirm)
  — keep the confirm (destructive, not reversible from this UI), but the menu
  hop is pure overhead. **Fix:** a directly-tappable delete affordance that
  still opens the same confirmation, cutting it to 2.
- **Sign In costs 2 "reach the sheet" taps before the actual flow starts** —
  it's nested inside the Dashboard's `View Options` menu (icon:
  `slider.horizontal.3`, reads as a display-settings menu, not an account
  one). **Fix:** a dedicated toolbar entry point (`person.crop.circle`).
- **Import's success path ends on a plain acknowledgement alert** (Merge/
  Replace → OK) — the Merge/Replace choice must stay a real decision, but the
  final OK is just dismissing an FYI. **Fix:** auto-dismissing toast for
  success, real blocking `alert` reserved for actual failures.
- **Inconsistent safety, not friction:** swipe-to-remove (system drill-down
  list, flat "All Games" list, macOS right-click) has **no confirmation at
  all**, while the identical destructive action from the detail view's `More`
  menu does. Not recommending removing the detail view's confirm — flagging
  that the fast paths are arguably *too* fast for a hard-to-recover action. A
  brief "Removed — Undo" toast on the swipe path would add a safety net
  without adding a blocking tap.
- **Hidden, not just compact:** on iOS, `PlatformCatalogRow`'s wishlist star
  only renders once an item is *already* wishlisted (`hovering` is
  macOS-only) — the only way to *add* a not-yet-wishlisted item to the
  wishlist from the system drill-down list is an undiscoverable leading swipe.
  Worth a persistent (if small) affordance on iOS too.
- **Inconsistent defaults, not exactly friction:** adding an *owned* item
  skips `QuickAddSheet` and silently defaults to Loose/Good in two places
  (`CatalogItemDetailView`, `AddToCollectionFlow`) but goes through the sheet
  in `SystemGamesList`. Fewer taps is good; worth deciding on purpose whether
  that inconsistency (and the differing defaults it produces) is intended.

None of this is implemented yet — pure audit, no code changed. Highest-value
first fix is the Condition/Completeness quick-picker, since it's the exact
pattern the user hit adding a real item and the fix already exists elsewhere
in the codebase to copy.

## Catalog browsing at scale

Raised 2026-09-13: `AddToCollectionFlow`'s catalog picker (and `CatalogSection`
generally) searches/lists the *entire* catalog flat, which won't hold up once
it's tens of thousands of games — hunting by name across everything gets
harder as the catalog grows, and it's already ~3,600 items. Likely direction:
browse **by system first** (the same system-first pattern `CollectionSection`
already uses for the owned collection — pick a platform, then search/scroll
within just that platform's titles) rather than one flat searchable list.
`SystemGamesList`'s `.all` scope already proves this shape works well for
browsing a single platform's full catalog (search + kind/sort filter + A–Z
scrubber). Worth doing before the catalog grows much further, since it's a
navigation-model change, not a small tweak, and gets harder to retrofit later.

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
- **SwiftLint** (already referenced as a stub command in `CLAUDE.md` but not
  actually installed/configured) would catch style-level smells (force
  unwraps, long functions, unused code) automatically and cheaply — worth
  actually setting up given the project explicitly mentions it as the intended
  tool.
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
