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
- **Partial box/manual state.** `CollectionItem.hasBox`/`.hasManual` (and
  `.hasInserts`/`.hasOriginalPackaging`) are plain booleans today — no way to
  note "have it, but it's not complete" (a manual missing pages, a box
  without flaps/inserts, only some of the original pieces). A simple
  checkbox/button per field to flag "incomplete/partial" alongside the
  existing yes/no would cover this without a bigger redesign of the
  completeness model.
- ~~**CSV export**~~ — done: `CollectionCSV` + "Export as CSV…" in the Backup menu.
- Per-item **price sparkline** + collection **value-over-time chart** — both need
  the feed to carry price history / periodic snapshots.

## Data feed & backend

- ~~**Disc-system catalogs**~~ (PS1 / PS2 / Dreamcast / GameCube) — done
  2026-09-14: user registered a Twitch/IGDB app and ran `igdb.mjs` for real,
  which surfaced (and got fixed) four real bugs the script had never actually
  hit before, since it had never been run end-to-end against live IGDB data:
  - `sleep`/`minYear`/`slugify` were `const` arrow functions declared near
    the bottom of the file but called from code that runs at the top —
    `ReferenceError: Cannot access 'sleep' before initialization` on the very
    first call. `const` isn't hoisted; converted all three to `function`
    declarations (which are).
  - `category = 0` (intended: "main games only, exclude DLC/bundles/etc.")
    matched ~0 games on every platform. Live IGDB responses omit `category`
    entirely (not `category: null`) on ordinary games — confirmed by direct
    `curl` against the API, not guessed. Fixed: `category = 0 | category = null`.
  - Same shape, worse: `release_dates.region` — the field the US-first
    filter relied on — is IGDB's old, silently-dead field, deprecated in
    favor of `release_region` (confirmed via IGDB's own schema, which
    documents the old field as `"DEPRECATED! Use release_region instead"`).
    Querying the dead field meant *every* release-date row looked
    region-less, and the original "no region data → keep" fallback let
    everything through once the `category` bug above was fixed — 100% of
    raw IGDB rows kept, no actual NA filtering happening. Fixed: query
    `release_region` instead; verified via `/v4/release_date_regions` that
    it reuses the old enum's ids (2 = north_america, 8 = worldwide) plus two
    new ones, so `NA_REGIONS` itself didn't need to change.
  - A small number of entries per platform (2-19) share a slug — distinct
    IGDB ids, either genuine near-duplicate catalog entries or titles that
    only differ by punctuation `slugify` strips (`"Final Fantasy"` vs.
    `"Final Fantasy ++"`). `CatalogSeedStore` throws on a duplicate slug, so
    added `deduplicateSlugs()`: appends `-<igdbID>` to every member of a
    colliding group, deterministic across re-runs.
  Final result: 13,154 items across all 10 platforms (6 re-enriched, 4 new),
  zero duplicate slugs, zero empty names, zero orphaned platform references —
  verified against the *actual* merged output (`node api/build/build.mjs`,
  `sources/local-file.mjs`'s curated+generated merge), not just the
  per-platform generated files in isolation.
- ~~Implement `api/build/pricing/pricecharting.mjs`~~ — done, but **dormant**:
  needs `PRICECHARTING_TOKEN` (paid) **and** `PRICECHARTING_ENABLE=1`, then fills
  in prices for un-priced games newest-first, `PRICECHARTING_MAX` calls/night.
  Until the user enables it the ~13,150 imported games still show "no pricing yet".
  Still worth doing: the nightly CSV path (Legendary tier) instead of per-item.
- ~~Bulk-sync perf~~ — re-measured 2026-09-14 against the real current feed
  (`api/dist/v1/catalog.json`, 10 platforms, 13,185 items) with a scratch
  `Testing` case decoding the feed and timing `CatalogSyncService.sync(into:)`
  on a fresh on-disk `ModelContainer`: decode 0.11s, first sync (inserts) 5.3s,
  no-op resync (nothing changed) 0.95s. First-launch sync is a noticeable but
  acceptable one-time pause (~5s, main actor, `Task.yield` every 400 keeps the
  UI responsive during it); every subsequent launch's no-op resync is under a
  second. Not moving `reconcile` to a background `ModelContext`/`ModelActor`
  for now — revisit only if the catalog grows enough to push first-sync past
  ~10s, since that's the threshold where a one-time pause starts to feel
  broken rather than a normal "importing catalog" moment.
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
- ~~**A live end-to-end test.**~~ Done 2026-09-15/16 — and it was worth
  doing exactly for the reason this item predicted: the REST docs didn't
  match reality. Found a real, previously-invisible bug: `completeSignIn`
  posted `{type, token, email}` to `/verify` (the shape for a *typed-in*
  numeric OTP) instead of `{type, token_hash}` (what email-link verification
  actually needs). Every attempt failed with the identical "Token has
  expired or is invalid," whether the token was 24 hours stale or 3 seconds
  fresh — which sent two days of live debugging chasing real-but-irrelevant
  leads (an email forwarder, the built-in sender's 2/hour rate limit, the
  `localhost:3000` Site URL default, even an unrelated Supabase maintenance
  window) before a raw `curl` with the corrected body against a fresh token
  returned an actual session. Fixed in `SupabaseAuthClient.swift` (commit
  `3f7ba7c` has the full account); see
  `RetroStacksTests/SupabaseAuthClientTests.swift` for the regression test.

  Confirming it through the real app UI surfaced three more real bugs, each
  found and fixed the same live way — no guessing, every one reproduced,
  diagnosed, and re-verified against the real server before moving on:
  - **PGRST102 "All object keys must match"** on the first real bulk push —
    `SupabaseCollectionRow` relied on Swift's synthesized `Encodable`, which
    omits a key entirely for a nil `Optional` instead of writing `null`, so
    two rows with different populated fields produced JSON objects with
    different key sets. Fixed with an explicit `encode(to:)`
    (`SupabaseCollectionSyncEngine.swift`, commit `3be8116`).
  - **Keychain session silently never persisted** — `SupabaseSessionStore
    .save()` gave up without telling its caller when `SecItemUpdate` failed
    on an existing item whose ACL belonged to a different code signature (no
    Apple Developer account here, so every Xcode rebuild re-signs locally
    and can invalidate the previous build's Keychain ACL — `errSecAuthFailed`
    /-25293). `AccountService` showed "signed in" from the in-memory session
    alone, then every sync call failed `.notSignedIn` the moment anything did
    a fresh Keychain read. Fixed by falling back to delete-then-add, which
    always gets a fresh ACL (`SupabaseSession.swift`, commit `4eb7923`).
  - **`42501`, RLS correctly rejecting a push** — not a bug, but real and
    worth recording: today's testing signed into three different Supabase
    accounts (`locdawg18@gmail.com`, a `+test2` alias, then `levidahlstrom
    @gmail.com`) against the same on-device collection with stable local
    IDs. Once rows existed under one account, syncing the same IDs while
    signed in as another correctly hit `auth.uid() = user_id`'s `USING`
    check. Resolved for this testing session with
    `truncate table public.collection_items, public.collection_item_photos;`
    — not a real multi-account collision an actual single-account user would
    ever hit.

  **Confirmed end to end for real** 2026-09-16: signed in through the actual
  app UI, ran a real sync, and independently verified in the Supabase Table
  Editor — 13 real rows under the right `user_id`, correct catalog slugs and
  status/condition/completeness. The whole pipeline (auth → Keychain →
  encode → RLS → land in the table) is proven working, not assumed.
- ~~**First-time "confirm your email" UX.**~~ Resolved 2026-09-16, and kept
  Confirm Email *on* deliberately (real proof of inbox ownership, a
  conscious choice over disabling it for convenience). Turned out to need no
  new code path at all: the confirm-signup email is the same `/verify` link
  shape as a magic link (`type=signup` vs `type=magiclink`), and
  `completeSignIn` already handles either generically once `token_hash` was
  fixed — confirmed live via `curl` (HTTP 200, account confirmed and signed
  in in one paste). Only real gap was `SignInSheet`'s copy assuming "a
  sign-in link" unconditionally; updated to say the first email may read
  "Confirm your signup" instead, and that it works the same way.
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
  "Contrast failed" findings inside `BreakdownBar` ("Breakdown by Platform",
  "$540", "SNES"), and 7 "`.secondary` at `.caption` nearly passes" warnings,
  which is the *default look of `.secondary` text everywhere in the app*, not
  a Dashboard bug — a design decision on how muted that should read, not
  something to change unilaterally (2026-09-14: this stayed a deliberate
  decision — kept as-is, but centralized behind `Color.mutedText`/
  `MutedTextStyle`, see the Muted-text entry below, so it's a one-line change
  later instead of a re-audit).
- **The 3 `BreakdownBar` contrast findings — real investigation, not fixed,
  2026-09-14.** The old theory ("a saturated bar washes out nearby text")
  never actually held up: "Breakdown by Platform" is the card's header, nowhere
  near any bar, and failed too. Tested for real: sampled actual screenshot
  pixels and found the header's `Label(...)` rendered its title visibly
  lighter than a plain `Text` at the same `.foregroundStyle(.primary)`
  (~(95,95,95), never true black) — a genuine, separate `Label`-rendering bug,
  fixed by switching to a manual icon+`Text` `HStack` (verified back to true
  near-black, ~(15,15,15), by the same pixel-sampling method). **The audit's
  finding on that exact text did not change** — still "Contrast failed" at
  genuinely near-black ink. That rules out literal rendered-pixel-color as
  whatever the audit is actually checking here. Root cause is still open;
  worth checking next whether it's specific to `GeometryReader`-based custom
  controls, or tied to a larger-Dynamic-Type-size rendering a same-size
  screenshot can't show. The `Label` fix was kept regardless — it's correct
  on its own even though it didn't clear the audit finding.

**Phase 6 (the automated gate) — done, as a ratchet, now on 6 screens.**
Each `*AccessibilityAuditTests.test*AccessibilityAudit` (Dashboard,
SystemGamesList, CollectionSection, CatalogSection, AddToCollectionFlow,
SidebarView — all in `NavigationTests.swift`) asserts
`findings.count <= knownFindingBaseline` (10 / 52 / 26 / 11 / 10 / 8
respectively) instead of only logging — catches any *new* regression on any
of the six immediately, without requiring the screens to be perfectly clean
first (Phase 5 hasn't happened yet). Lower each baseline as its findings get
fixed for real.

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

**Phase 4, extended to 3 more screens — done 2026-09-13, none of the new
findings fixed yet.** Same real-audit technique (`performAccessibilityAudit`
+ `.detailedDescription`, not hand-guessing), same ratchet pattern, now in
`SystemGamesListAccessibilityAuditTests` / `CollectionSectionAccessibilityAuditTests`
/ `CatalogSectionAccessibilityAuditTests` (`NavigationTests.swift`, alongside
the original Dashboard one):

- **SystemGamesList: 52 findings. CollectionSection: 26. CatalogSection: 11.**
  All three are overwhelmingly the *same* systemic pattern Dashboard's audit
  already named and deferred as a design decision — `.secondary` text at
  `.caption`/`.caption2` size — just recurring at much higher volume because
  these screens repeat it once per row/tile instead of Dashboard's few
  summary numbers. This is now confirmed empirically across 4 screens, not a
  Dashboard-only theory.
- ~~`CompletenessBadge` / `ConditionLabel` / `StatusBadge` badge-wash
  contrast~~ — investigated for real 2026-09-14 (see `Badges.swift`'s doc
  comment for the full account). Confirmed live: badges render their color
  as *text on that same color's own `.opacity(0.18)` capsule background* — a
  genuinely different, harder target than the page-background case
  gold/green/red were originally tuned for. Sampled real screenshot pixels
  for all 7 badge colors against their own wash and found every one fell
  short of 4.5:1, some badly (`.orange`/`.mint`, never adjusted before, measured
  ~1.6-1.7:1). Retuned gold/green/red darker and added
  `AccentBlue`/`AccentPurple`/`AccentOrange`/`AccentMint`, all targeting
  ~5.2:1 against their own wash, verified by re-sampling actual rendered
  pixels post-fix (not just trusting the math). **The OS audit's finding on
  "CIB" didn't change even though the color measurably did** — same
  unresolved-by-a-real-fix pattern as `BreakdownBar`'s header text below.
  The color fixes are kept (genuinely better contrast, independently
  verified) but this is now real evidence across *two* unrelated contexts
  that `performAccessibilityAudit()`'s contrast check isn't simply measuring
  the current static-frame composited pixel color — chasing exact
  colorimetric values further isn't a reliable strategy without first
  understanding what the audit actually checks (Xcode's interactive
  Accessibility Inspector might show more than XCUITest's
  `.detailedDescription` does).
- **One CollectionSection oddity**: every row shows the same fields
  (item count, %, $ amount) but only *one* row (Nintendo GameCube) hard-fails
  contrast on them while the rest only soft-warn — possibly a
  selection/hover-highlight background making an already-borderline color
  actually fail there. Not investigated further this pass.
- ~~`CatalogSection`'s missing accessible nav title on iOS-compact~~ — fixed
  2026-09-14, and this one's root cause was real and findable (unlike the two
  contrast mysteries above): `CatalogSection.body` applied `.navigationTitle`
  to the *outer* `NavigationSplitView`, not to the visible column. On
  iOS-compact, where the split view collapses to one column, a title on the
  outer container never propagates to whichever column is actually shown —
  `CollectionSection`'s plain `NavigationStack` never had this problem since
  there's no collapse behavior to lose the title across. Moved
  `.navigationTitle` (and `.searchable`/`.toolbar`, which belong with it)
  onto `contentColumn` directly. Verified for real, not assumed: the UI test
  that used to need a content-based workaround
  (`CatalogSectionAccessibilityAuditTests`) now passes with the same
  `waitForScreen("Catalog", in: app)` check every other screen uses. Still
  worth a real VoiceOver check on a real device before calling this screen
  fully done — this fixes what the accessibility tree reports, not a
  substitute for hearing it.

**Muted-text contrast — made a decision, and centralized it, 2026-09-14.**
User's call: keep the current subtler `.secondary` look for now rather than
darkening it for compliance — but wanted a single, centralized place to flip
later without hunting through screens, since the pattern above is now
confirmed everywhere. Added `App/MutedTextStyle.swift`: a `MutedTextStyle`
enum (`.subtle` / `.compliant`, `current` hardcoded to `.subtle`) plus
`Color.mutedText` (declared as `extension ShapeStyle where Self == Color`,
matching how SwiftUI defines its own `.secondary`/`.red`/etc. — a plain
`Color` extension resolved in most call sites but not all of them, a real
Swift inference gotcha worth remembering), backed by a new
`MutedTextCompliant` colorset (hand-computed light-mode gray at ~4.94:1
against white, comfortably over the 4.5:1 floor; dark-mode value is an
*approximation* of system `secondaryLabel` dark, not sampled — re-verify
before ever flipping `current` to `.compliant` for real). Every `.secondary`
call site in `Views/` styling actual text (45 of them) now goes through
`.mutedText` instead — icon/control-state tints (wishlist star, checkmark
toggle "off" states) deliberately left as plain `.secondary`, since those are
a control-state semantic, not muted text. Verified behavior-preserving:
all 4 accessibility-audit ratchets (10/52/26/11) held exactly, since
`.subtle` renders identically to bare `.secondary`.

~~`AddToCollectionFlow` and `SidebarView` accessibility passes~~ — audited
2026-09-14, both now on the same ratchet as the other 4 screens
(`AddToCollectionAccessibilityAuditTests` / `SidebarViewAccessibilityAuditTests`
in `NavigationTests.swift`), nothing fixed yet:

- **AddToCollectionFlow: 10 findings** (default platform-picker list only —
  the barcode scanner and flat search-results list are separate sub-screens,
  not covered by this pass). 8 are the same systemic `.mutedText`/`.caption`
  pattern (`CatalogPlatformRow`'s "N catalog entries" subtitle) already
  covered by the muted-text decision above. 1 is the toolbar "Done" button
  flagged for Dynamic Type despite no font override — not chased, likely the
  same audit-internal quirk as the `Label`/`NavigationLink` cases elsewhere.
  1 is a genuine single-row outlier ("Sega Dreamcast" hard-fails contrast
  while every other platform row doesn't) — same shape as
  `CollectionSectionAccessibilityAuditTests`'s Nintendo GameCube anomaly, not
  investigated further for the same reason (see below).
- **SidebarView: 8 findings, and a real methodology finding.** Unlike every
  other screen, `RootView.splitLayout` never shows the sidebar alone on a
  regular-width destination — the detail pane (Dashboard by default) is
  always on screen too, and `performAccessibilityAudit` audits everything
  visible, not one view's subtree. A raw run came back with 67 findings,
  overwhelmingly Dashboard content already tracked by its own baseline above
  — counting those here too would double-count. The test now filters to just
  the 4 `sidebar.<section>`-identified rows, giving 8 real findings: **every
  one of the 4 rows** (not just an outlier) hard-fails both "Contrast failed"
  and "may be clipped at larger Dynamic Type sizes". `row(_:badge:)` builds
  each from a plain `Label(...)` inside a stock `List(selection:)` +
  `.listStyle(.sidebar)` — about as default as SwiftUI gets, so this is
  systemic across the whole screen, not a one-off. Worth a real look, but not
  chased via pixel-sampling this pass: two separate investigations elsewhere
  this session (`BreakdownBar`'s header, `Badges.swift`'s colors) already
  showed this audit's "Contrast failed" doesn't reliably track actual
  rendered pixel color, so a third blind attempt isn't a good use of time
  without first understanding what the audit actually measures. Must be run
  against a **regular-width** destination (e.g. `-destination 'platform=iOS
  Simulator,name=iPad (A16)'`) — the standard iPhone 17 destination this
  suite otherwise uses never mounts `SidebarView` at all (iOS-compact falls
  back to `RootView.tabLayout`).

~~**`NavigationTests`'s original two cases were macOS-only**~~ — fixed
2026-09-14. Both checked `app.windows[title]` to confirm they landed on a
screen — a macOS-only pattern (each pushed screen gets its own titled
`NSWindow` there). Running them on the iOS Simulator destination for the
first time this session (previously only macOS-hosted, user's own Terminal —
see "Automated leak testing" for why macOS-hosted `xcodebuild test` hangs in
an automated session) failed both cases immediately: iOS never creates a
second window, so the query never matched anything. Swapped in the same
`waitForScreen` helper the 3 newer audit tests already use (`#if os(macOS)`
window title, `#else` navigation-bar title) — verified passing on iOS for
real, not assumed.

`AppWalkthroughTests` deliberately left as-is (still macOS-only,
`app.windows[title]` + sidebar-identifier navigation): it exists specifically
to drive `Scripts/leak-check.sh`'s `xctrace`/Instruments Leaks-attach
workflow, which is itself a macOS-specific tool — backporting its navigation
to iOS wouldn't make the thing it's *for* any more cross-platform, so it
wasn't worth the bigger refactor (tab-bar navigation fallback for every
sidebar-identifier tap) that would need.

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
of everything (~3,600 entries when this was built, ~13,150 now that the
disc-system catalogs landed — the design's payoff only grew). Typing into the search field is
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

~~Correction 2026-09-17~~: that last claim — "`SystemGamesList`'s per-platform
search" as an already-proven pattern — was stale/wrong. `SystemGamesList`
never had its own `.searchable()`; it only ever showed whatever a *parent*
screen's search bar happened to propagate down the nav stack, inconsistent
depending on entry point. Found from real usage feedback ("a title search
would be useful browsing a system") — the filter logic already handled
search text correctly, it just had no always-present local source. Fixed:
see "Real-usage feedback" below.

## Real-usage feedback (2026-09-17, first live sync + collection session)

First real-world session using the app for actual collection work (post the
end-to-end sync fixes above). Four items came back:

- ~~**Slowness adding/removing titles.**~~ Fixed. `SystemGamesList.catalog`
  (filter + sort over a whole platform's catalog, up to ~1,900 items for
  SNES) ran as a plain computed property, recomputed on *every* SwiftUI body
  evaluation — since `liveEntries` is an unscoped `@Query` of every
  `CollectionItem`, that fired on every add/remove/edit *anywhere* in the
  app, not just this screen. Fine at ~400 items/platform (pre-IGDB), noticeably
  slow at ~5x that. Cached in `@State`, refreshed only via `.task(id:)` on
  real dependency changes.
- ~~**Per-system title search.**~~ Fixed — see the correction above.
  `SystemGamesList` now has its own `.searchable()` field, always present.
- ~~**Manual hide/exclude for catalog slop.**~~ Fixed, as a fast-turnaround
  alternative to a full licensed/unlicensed heuristic (still open, below):
  `CatalogItem.isHidden`, toggled via leading swipe (iOS) / context menu
  (macOS), with a "Show Hidden Items" toggle in the filter menu to review/
  unhide. Purely local — never touched by `CatalogSyncService.reconcile`.
- ~~**Variants (5-screw NES, black-label carts, etc.) as distinct catalog
  entries.**~~ Done — see "Catalog goes live in Supabase" → Phase 4 below for
  how it actually shipped. User's call: new `CatalogItem` rows per variant,
  not a free-text field on the owned item, mixing IGDB-sourced data with
  hand-created rows. Checked real candidates before committing to anything:
  IGDB's own docs don't model this granularity, and PriceCharting's
  *website* clearly does (Zelda alone has 5-screw/3-screw/gold-vs-gray/
  Rev-A/SOQ variants listed) but its public API doesn't expose any of it
  (verified via its real docs, not assumed) — so this stays hand-curated for
  the foreseeable future, not auto-pulled from anywhere.

  This grew into a much bigger architecture decision: the catalog moved from
  a static JSON feed to a live Supabase-backed table with a real public/
  private split, not a bolt-on "variants" feature. See "Catalog goes live in
  Supabase" below for the full account.
- **Licensed/unlicensed filtering.** User's call: a heuristic using IGDB's
  `involved_companies.publisher` as a first signal (unpublished likely means
  homebrew/ROM-hack, like NES "2048"), refined later. Not verified against
  real data yet — needs a live IGDB query (I don't hold IGDB credentials
  myself; every real API check this project has done went through the user
  running `curl` and pasting the response back, same as the `category`/
  `release_region` bugs found in `igdb.mjs`). Concretely: pull `2048`'s IGDB
  entry with `fields name,involved_companies.publisher,involved_companies
  .company.name;` and see whether it actually lacks a credited publisher, or
  whether the signal is noisier than expected, before writing an ingest-time
  filter around it.

## Catalog goes live in Supabase (2026-09-17)

Prompted by the variant-catalog-entry request above: the catalog was a
static JSON feed (built by `api/build/*.mjs`, downloaded read-only) with no
way for a user to add their own rows at all. Real architecture change, not
a bolt-on — see `supabase/schema.sql`'s "Phase 2" section for the full
account, commit `72aae82` for the schema and `f0d521f` for the migration.

- ~~**Phase 1 — schema + RLS.**~~ Done. One table (`catalog_items`), split
  by `owner_user_id` (`null` = public/shared, set = private to that user).
  A regular user can only ever write their own rows — never a public one
  directly, not even to "submit" something; that's a separate admin-gated
  `promote_catalog_item_to_public()` (`SECURITY DEFINER`, checks a new
  `admins` table with no RLS-exposed read/write of its own). Verified live,
  not just applied: confirmed the anon key genuinely can't insert a public
  row (`42501`), and that a real select against the table works.
- ~~**Phase 2 — migrate the existing catalog in.**~~ Done. Found a real bug
  before it could bite at scale: PostgREST's own upsert (`?on_conflict=slug`)
  can't target a *partial* unique index (Postgres needs an exact index-shape
  match, predicate included) — confirmed against the real table (`42P10`)
  before writing around it, not assumed. Fixed with a hand-written
  `upsert_public_catalog_items(jsonb)` function using the real
  `ON CONFLICT (slug) WHERE owner_user_id IS NULL` syntax only raw SQL can
  express, locked to `service_role` via explicit `revoke`/`grant` (checked
  the anon key really can't call it either). `api/build/migrate-catalog-to
  -supabase.mjs` batches the upsert (500/call); a full run migrated all
  13,185 items, verified per-platform against the source JSON — all 10
  platforms match exactly, not just a total-count check.
- ~~**Phase 3 — rewrite the app's catalog sync.**~~ Done. New
  `SupabaseCatalogRepository` (drop-in `CatalogRepository`, same contract
  `RemoteCatalogRepository` had) paginates `catalog_items` (PostgREST caps a
  response at 1,000 rows, so this loops on `offset`) — public rows always,
  plus the signed-in user's own private rows in the same fetch, since that's
  just what the SELECT RLS policy already returns for whichever key/token is
  used. Platforms stay bundled/local, read from the same seed
  `CatalogSeedStore` already uses, so `reconcile`'s platform handling didn't
  need to change at all — only where `items` comes from did.
  `CatalogSyncService.shared` now defaults to it. Full-catalog fetch (13,185
  items, ~13 pages) verified live at ~5-7s, comparable to the old static-feed
  path, not a regression. `reconcile` itself untouched — still additive-only
  (see the cleanup item below for why that's now worth revisiting).
- ~~**Phase 4 — "add a custom catalog entry" UI.**~~ Done. The read side came
  free from Phase 3 (RLS's own SELECT policy already returns the signed-in
  user's private rows alongside public ones); this phase was the write side.
  `CatalogItem.ownerUserID`/`FeedItem.ownerUserID` thread the server's
  `owner_user_id` through decode and `reconcile` so the app can tell "mine"
  apart from public. `CustomCatalogItemService.create` does a plain
  authenticated `INSERT` (not an offline change-tracking queue like
  `CollectionSyncEngine` — a rare, explicit action doesn't need one);
  `CustomCatalogItemActions.create` posts it then writes the server's own
  response straight into SwiftData, so local and remote can't diverge on a
  partial failure. Slugs are client-generated (`makeSlug`: a readable base
  plus a short random suffix) since only per-owner uniqueness matters for a
  private row. One form (`CustomCatalogItemSheet`) covers both "variant of
  an existing item" (`CatalogItemDetailView`'s new "Add a Variant" button,
  platform/kind locked) and "wholly new entry" (`CatalogSection`'s toolbar
  "Add Custom Entry"); both disabled with a tooltip when signed out, since
  RLS's `catalog_items_insert_own` policy only ever accepts
  `owner_user_id = auth.uid()`. Verified live against the real table (not
  just applied): the exact JSON shape the app sends inserts cleanly (`201`),
  a duplicate slug under the same owner correctly conflicts (`409`,
  `catalog_items_private_slug_idx`), the same slug as an existing *public*
  row does **not** false-conflict (different partial index, as designed),
  and the anon key is correctly rejected by RLS (`42501`) — scratch rows
  cleaned up after.
- **Phase 5 — admin promotion surface.** Half-started 2026-09-17, from a
  different direction than originally planned: not promoting a private row
  to public, but *curating* the existing public catalog — excluding
  IGDB-import junk (bootlegs, ROM hacks, non-cartridge entries like "8 Bit
  Son of a Bitch" on NES) for every user, not just locally. New
  `admin_exclude_catalog_items`/`admin_restore_catalog_items` (bulk
  soft-delete-by-slug, same `deleted_at` tombstone every sync path already
  respects — reversible) and `is_admin()` (lets the app gate the UI without
  reading the locked-down `admins` table directly), all in `schema.sql`,
  same `SECURITY DEFINER` pattern as `promote_catalog_item_to_public`.
  `AdminCatalogCurationService` + a new admin-only "Exclude" action in
  `SystemGamesList`'s existing bulk-select mode (behind a confirmation
  dialog) are wired up app-side. **Not yet run against the real schema** —
  needs `supabase/schema.sql` re-applied in the SQL Editor before the RPCs
  exist, then a real click-through verification. The original
  `promote_catalog_item_to_public` path (private → public) is still
  untouched and still not built into any UI.
  - Real data check while scoping this (queried the live local store
    directly, not guessed): of NES's 1,694 catalog entries, 981 have
    `releaseYearNA <= 1995` (NES's real commercial window), 583 are after
    1995, and 130 have no release year at all — a real if imperfect
    (undercounts the user's ~890 estimate a bit) starting split.
  - ~~`involved_companies.publisher`-missing as a signal~~ **Checked live
    against real IGDB data (user ran the `curl` calls) and ruled out** —
    doesn't work. IGDB is community-contributed and lets anyone list
    themselves as a "company": every one of 5 real "Super Mario Bros. 3"
    ROM hacks checked (Alpha, Xmas Edition, A New Journey, "+", a "Lost
    Levels" hack) has `involved_companies` populated with the hacker's own
    handle ("Infidelity", "sukoritai", "xerox519", …) — structurally
    identical to a real publisher credit, so "no companies credited"
    doesn't reliably distinguish a hack from a real release.
  - **`first_release_date` is the real signal, and it's clean.** Same 6
    real-vs-hack comparison: the real Super Mario Bros. 3 has
    `1988-10-23` — the actual historical NES release date. Every hack is
    either missing the field entirely or dated years to decades later
    (2005, 2015, 2016, 2022, 2023) — "8 Bit Son-of-a-Bitch" itself is
    `2022-01-01`, an exact midnight-Jan-1 placeholder. `category`/
    `version_parent` (IGDB's own "is this a mod/hack" fields) are already
    filtered at ingest time and evidently aren't catching these — neither
    is set on any of the hacks checked — so release-date is doing real work
    here that IGDB's own structured fields don't.
  - ~~A dedicated "jump to suspicious" filter, instead of sort + scroll~~
    Done — user's own follow-up: publisher count alone (their original
    idea) isn't reliable either. Checked live: NES's top 40 publishers by
    count are *all* real (Nintendo down through Milton Bradley, including
    real-but-unlicensed ones like Active Enterprises/Camerica/Color Dreams
    and real modern homebrew studios like Mega Cat Studios/The Mojon
    Twins/Piko Interactive) — the signal is in the *tail*, not the head:
    460 distinct publisher names on NES, 279 of them appearing on exactly
    one item, another 71 on exactly two. Publishers appearing ≤3 times
    cover 591 items; add the 330 "(none)" items and that's 921 — close to
    the user's original ~890 estimate. Combined with the release-date
    signal above (requiring *both*, not either — a real obscure publisher
    with a correct period date shouldn't get flagged just for being
    small), built as a real "Review Candidates Only" toggle in
    `SystemGamesList`'s filter menu
    (`SystemGamesListReviewCandidateTests` locks the decision boundary
    down with constructed fixtures, not just the live spot-checks above).
    Verified against the real store before shipping: 562 NES items match
    both signals — a real, sizeable narrowing from 1,694, and Super Mario
    Bros. 3/Legend of Zelda/etc. correctly stay out while the SMB3 hack
    family and similar correctly get flagged. `computeCatalog`/
    `ascendingCompare`/`isReviewCandidate`/`indexLetter` split into a new
    `SystemGamesListCatalog.swift` in the process — the new heuristic
    pushed `SystemGamesList`'s `type_body_length` from a tolerated warning
    into a hard lint error (615 lines against the 600 threshold), so this
    wasn't optional this time. Not yet run against the app for a real
    click-through — worth doing before relying on it for the actual NES
    cleanup pass.
- ~~**Cleanup: stale local catalog items never get pruned.**~~ Fixed
  2026-09-18 — stopped being a "not a priority yet" item the moment the
  admin-exclude feature made it directly visible: excluding NES bootlegs
  for everyone didn't move a single count on screen (About System Card,
  the platform picker's "N catalog entries", …) except the one already-
  filtered browse list, since nothing pruned the stale local row. User's
  own instinct, confirmed before building: the server side was already
  correct (`SupabaseCatalogRepository` already filters `deleted_at
  is.null`), so the fix belongs in `reconcile`, not scattered client-side
  checks. `reconcile` now prunes local *public* items missing from a
  fresh feed — deletes outright when unowned (the common case), falls
  back to `isHidden = true` only when someone's collection references it
  (a hard delete would cascade-delete their real `CollectionItem`).
  Private items are never pruned this way (their absence from one fetch
  usually just means the viewer is signed out, not that the server
  deleted them). `Platform.visibleCatalogItems(includeHidden:)` is the
  one narrow client-side backstop left, for that same rare owned+excluded
  case. Four new `CatalogSyncServiceTests` lock the boundary down. Should
  also finally clear the original 492-item Atari 2600 slug-scheme
  discrepancy on the next sync, as a side effect — not separately
  verified yet.
  - **Follow-up, same day: the fix above wasn't actually enough, twice
    over.** User reported the real numbers after syncing (1604 NES games,
    not the ~1047 the server actually has) — checked against the live
    server directly (`curl`, not guessed) to confirm 1047 live / 544
    excluded / 1591 total public NES rows, then against the real local
    store, which found two distinct bugs:
    - **A second, un-consolidated raw-count spot.** `Platform.games`
      (feeding Dashboard's platform breakdown — `catalogGameCount`,
      `remainingValue`, `completionRatio` in `CollectionStats
      .systemSummaries`) filtered raw `catalogItems` directly, same shape
      as the bug already fixed once for `AboutSystemCard`. Browse
      Catalog's own filter (`CatalogBrowseViewModel.apply`) never checked
      `isHidden` at all. User's call: one source of truth, not another
      patched call site. `Platform.consoles`/`.games`/`.accessories`/
      `.items(of:)` are now all defined *in terms of*
      `visibleCatalogItems()` — there's nowhere left to filter
      `catalogItems` by kind except through it. `CatalogBrowseViewModel`
      got its own `showHidden` (plain stored property, deliberately
      independent of `SystemGamesList`'s — matches every other filter on
      that view model already resetting per visit).
    - **The exclude action's own safe-delete-or-hide check was wrong.**
      Checked local data directly: 561 NES items hidden, 0 deleted — every
      single excluded item took the "someone owns it" branch. Root cause:
      `CollectionActions.remove` only *soft*-deletes (`markDeleted()`,
      sets `deletedAt`), so the ~560 items from the earlier accidental-
      bulk-add-then-undo incident still had a tombstoned `CollectionItem`
      attached, and the check used raw `collectionEntries` (which counts
      tombstones) instead of `liveEntries` (which doesn't). Fixed in both
      `commitBulkExclude` and `reconcile`'s pruning pass — already-
      mis-hidden items self-correct (actually delete) on the next sync,
      since pruning re-evaluates every local item every time, no separate
      migration needed. Two more `CatalogSyncServiceTests` (one
      reproducing the tombstone case exactly) plus a new
      `HiddenCatalogItemVisibilityTests` lock both fixes down.

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

## Real-usage feedback, round 2 (2026-09-17, first pass testing Phase 4)

- ~~**`CatalogSection.items` recomputed on every body pass.**~~ Fixed. Same
  bug class as `SystemGamesList.cachedCatalog` above, just missed when
  `CatalogSection` was built: `viewModel.apply(to: allItems)` filters/sorts
  up to ~13,150 items as a plain computed property, and `allItems` is an
  unscoped `@Query`, so any `CatalogItem` change anywhere re-triggers it.
  Cached in `@State`, refreshed via `.task(id:)` on real filter/sort/search
  changes, seeded synchronously in `.onAppear` too (avoids a one-frame
  "No Matches" flash when arriving with a platform already picked, e.g. from
  Dashboard's breakdown row).
- **Sidebar navigation lag (~2s per click, macOS) — partially investigated,
  not fully explained.** Measured for real rather than guessed: a scratch
  test opened the actual on-disk dev store (13k+ `CatalogItem` rows) fresh
  and timed `context.fetch` for `CatalogItem`/`Platform`/`CollectionItem`
  plus touching every item's `.platform` relationship — **under 1 second
  total**, so the raw fetch isn't the ~2s cost by itself. Leading
  hypothesis, not yet confirmed: `RootView.sectionView`'s `switch` returns a
  different concrete view type per `AppSection` case, so every sidebar
  click fully tears down and reconstructs whichever screen you're
  leaving/entering — no `@Query`/`@State` survives across a switch, all of
  it re-runs from scratch every time, on every destination (matches the
  report that it's not just Catalog that's slow). A real fix would mean
  keeping all section views alive simultaneously (e.g. a `ZStack` +
  `.hidden()`/opacity instead of a destructive `switch`) rather than
  rebuilding on every click — a real architecture change with a real
  tradeoff (filters/scroll position would then persist across tab switches
  instead of always starting fresh), so not done without discussing it
  first. The `CatalogSection.items` fix above is real and worth keeping
  regardless, but shouldn't be assumed to be the whole story here.
- ~~**macOS Browse Catalog toolbar: "+"/Kind picker/Filter menu visibly
  clipped.**~~ Attempted fix, **not yet visually confirmed** — no safe way
  to screenshot the live macOS app from this session (screen capture here
  is restricted to app-window-only, declined rather than risk a repeat of
  the earlier full-desktop-capture near-miss logged elsewhere in this
  project's history), so this was diagnosed from a user-provided screenshot
  and code reading only. Three bare `ToolbarItem`s (`Button` + `Picker` +
  `Menu`) regrouped into one explicit `ToolbarItemGroup`, since macOS's
  automatic glass-capsule grouping across dissimilar adjacent controls is
  the likeliest cause — no `.clipped()`/fixed-height modifier found
  anywhere in the toolbar's own code to explain it directly. Needs a real
  look after rebuilding.
- ~~**"Add a custom entry" only reachable from Browse Catalog, not from "Add
  to Collection."**~~ Fixed. The user's own framing: this flow is exactly
  the moment someone realizes the catalog is missing something, so it
  should offer to create it right there, not just on the standalone browse
  screen. `CustomCatalogItemSheet` gained `initialName` (prefills from
  whatever was already typed into the search field) and `onCreated`
  (fires after a successful save) so `AddToCollectionFlow` can chain
  straight into its own existing `add(_:)` — the same `QuickAddSheet`-or-
  direct-add path every other catalog item in this flow already goes
  through, so creating a custom entry here actually adds it to the
  collection/wishlist, not just creates it. A "Can't find it? Add a Custom
  Entry" row sits at the bottom of the platform-browse list, and the search
  results list shows a stronger "No matches — Add '\<query\>' as a Custom
  Entry" variant when nothing matched.
- ~~**System list → system detail navigation, ~4s freeze; "Add to Collection"
  noticeably laggy — confirmed as real main-thread blocking, not perceived.**~~
  Quick mitigation done; the real fix is below, deferred. Measured for real
  against the on-disk dev store (a scratch test replicating the exact work
  each does): `SystemGamesList.init`'s synchronous seed (`platform
  .catalogItems`'s first access — a SwiftData relationship fault over
  thousands of rows post-IGDB — then a filter+sort) took **3.37s and 1.43s**
  across two runs, matching the reported ~4s almost exactly; `CollectionActions
  .add`'s `context.save()` took **0.87s and 1.44s**, matching "noticeably
  laggy" rather than "frozen." Both run synchronously on `@MainActor`, so
  they block the whole app, not just their own screen. Fixed *for
  `SystemGamesList`*: stopped seeding `cachedCatalog` synchronously in
  `init` (was there specifically to avoid a one-frame empty-state flash —
  a bad tradeoff once the synchronous cost is seconds, not a frame). A new
  `hasLoadedCatalog` flag now distinguishes "still loading" from "genuinely
  empty" so `.task(id:)` populating the cache asynchronously shows a real
  `ProgressView` instead of either a wrong empty-state or nothing. This
  makes the *navigation transition* itself smooth — the screen appears
  immediately — but the underlying fault+sort still takes the same 1-3+
  seconds once it starts running; it's deferred off the critical path of
  the push animation, not made faster.
- **Follow-up, not done: the actual non-blocking fix (background `ModelActor`)
  and a possible catalog/collection store split.** Two related but distinct
  pieces of real work, both flagged rather than rushed into this pass given
  their size/risk:
  - Move `SystemGamesList`'s catalog fault+sort (and anywhere else with the
    same shape) to a background `ModelActor` with its own `ModelContext` on
    the same store, fetching via a predicate (`#Predicate<CatalogItem> {
    $0.platform?.slug == someSlug }`, matching `CatalogBrowseViewModel
    .apply`'s existing pattern) instead of touching the live `platform
    .catalogItems` relationship on the main actor at all — resolving back to
    live `@Model` references via `PersistentIdentifier` once back on
    `@MainActor`. This is the piece that would make the 1-3s cost actually
    disappear (or at least move off the main thread) rather than just being
    deferred past the navigation animation.
  - `CollectionActions.add`'s `~1s` save is harder to fix the same way —
    SwiftData saves generally need to happen on the context's own actor, and
    a lot of code assumes `CollectionActions.add`/`.remove` complete
    synchronously on `@MainActor`. Worth investigating whether splitting the
    catalog (huge, rarely-written) and the collection (small, frequently
    written) into two separate `ModelContainer`s/persistent stores would let
    a collection save avoid considering the whole 13k+-row catalog graph at
    all — unconfirmed whether that's actually *why* the save is slow (could
    also just be inherent SQLite/WAL overhead at this store size), so this
    needs its own real measurement before committing to the bigger
    persistent-store-split architecture change it implies.
