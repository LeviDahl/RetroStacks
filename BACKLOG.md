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
- ~~**Real bug, user-reported 2026-09-19: `QuickAddSheet` (the "+" add
  modal) never actually set `hasBox`/`hasManual`.**~~ Fixed. The modal only
  ever had a "Completeness" preset picker (Loose/Boxed/CIB/Sealed) —
  `CollectionActions.add` had no `hasBox`/`hasManual` parameters at all, so
  picking "CIB" left the item's actual checklist booleans `false`
  regardless, disconnected from the full edit view's real "Box"/"Manual"
  toggles. Mattered for a concrete reason, not just checklist cosmetics —
  user's own point: "each piece has different pricing on PriceCharting" —
  `CatalogItem.referenceValue(for:)` picks the loose/CIB/sealed price tier
  straight from `completeness`, so getting this right is a real pricing-
  accuracy bug, not just a display one. Fixed both directions, since a
  preset alone can't express every real case (box but no manual, or the
  reverse, which has no clean `Completeness` case at all): `CollectionActions
  .add` gained `hasBox`/`hasManual` parameters (threaded through to
  `CollectionItem`'s own init, which already had them); `QuickAddSheet`
  gained explicit Box/Manual toggles alongside the existing preset picker —
  picking a preset sets both to match (quick path, user's own ask: "pick
  CIB and it auto-fills the checkboxes"), and each toggle stays
  independently changeable afterward, re-deriving `completeness` to the
  closest fit (falls back to `.loose` for the no-exact-match "manual only"
  case — `hasManual` itself still stays accurate even though the price
  tier can't represent it exactly). New `CollectionActionsTests.swift`
  locks down `add` actually persisting what it's given. Full suite clean,
  both platforms build.
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
`findings.count <= knownFindingBaseline` (11 / 52 / 28 / 11 / 10 / 4
respectively — current as of 2026-09-19) instead of only logging — catches any *new* regression on any
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
  IGDB's own docs don't model this granularity. At the time, PriceCharting's
  *website* clearly did (Zelda alone has 5-screw/3-screw/gold-vs-gray/
  Rev-A/SOQ variants listed) but its public API was believed not to expose
  any of it — so this stayed hand-curated.
  ~~Correction 2026-09-18~~: that API claim doesn't hold up once actually
  subscribed and tested live — a real `/api/products` search returned `NES
  | Legend of Zelda [5 Screw]` directly. Variant tags *do* show up in
  `product-name` for at least well-documented variants; the original check
  was reading the docs, not calling the API with a paid token. Still hand-
  curated for now (nothing auto-pulls variant data into the catalog), but
  the "API can't do this" premise was wrong, worth remembering if this gets
  revisited.

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
  - ~~A stronger-than-heuristic signal, once willing to pay for it~~ Done
    2026-09-18: user subscribed to PriceCharting's $49/mo Legendary tier
    specifically to test this. New `api/build/pricecharting-catalog-match
    .mjs` — takes the same review-candidates heuristic (ported to JS, kept
    in sync by hand with `SystemGamesListCatalog.swift`'s Swift version,
    no shared source between the app and this build pipeline), searches
    PriceCharting's live `/api/products` for each candidate, and writes a
    report (`api/data/pricecharting-match-<platform>.json`, gitignored —
    point-in-time, not source data) suggesting keep/exclude per item.
    Grew a real `--execute` flag the same day (see below) that PATCHes
    `deleted_at` directly via the service-role key — the RPC path
    (`admin_exclude_catalog_items`) can't be called this way since
    `auth.uid()` is null for service-role requests, so this bypasses RLS
    directly instead, same end state.
    - First real run against NES's *current* (already-cleaned-up) catalog:
      only 6 review candidates remained (down from ~562 before the user's
      earlier bulk-exclude pass — a real confirmation that pass worked).
      2 matched PriceCharting exactly (`Battle Kid 2: Mountain of Torment
      [Homebrew]`, `Nomolos: Storming the Catsle [Homebrew]` — both real
      RetroUSB homebrew with genuine sales data) and correctly suggested
      "keep"; 4 had no PriceCharting match at all and suggested "exclude."
      One of those four (`Larry and the Long Look for a Luscious Lover`,
      also credited to RetroUSB, a publisher with *other* confirmed real
      releases) is a good example of why this stays a suggestion, not an
      auto-exclude — could be a genuinely obscure real release PriceCharting
      hasn't priced yet, not necessarily fake.
    - Region signal confirmed usable the same run (see the EU/JP item
      above): PriceCharting splits releases into regional console names
      (`NES` / `PAL NES` / `Famicom`) rather than a per-item field — the
      script records which one a match came from. Only `nes`'s mapping is
      verified so far (`CONSOLE_NAMES` in the script) — add more platforms
      only after confirming their console-name pattern live, not by
      guessing the naming convention from NES's.
    - No bulk "everything for a platform" API endpoint exists (confirmed
      live, not assumed from docs) — `/api/products` search caps around
      100 results per query. Fine for a review-candidates-sized list (a
      few hundred at most); would need the CSV bulk export (also Legendary-
      tier, a separate logged-in-website download, not a token-authenticated
      URL) if this ever needs to check the *whole* catalog rather than just
      the flagged subset.
    - **Real bug found 2026-09-18 from a live example, not a guess:** user
      spotted N64 item `n64-15` ("15" by "MorningStorm64", 2022) still in
      the public catalog and asked how it survived review. Traced it to
      `findReviewCandidates`'s AND-gate — `publisherIsRare AND (yearMissing
      OR yearLate)` — where a hard `≤3` publisher-count veto could suppress
      an unambiguous late-year signal entirely. MorningStorm64 had 6 N64
      entries, one over the threshold, so the 2022 release year (vs. N64's
      2002 `discontinuedYearNA`) never got consulted. Checked the blast
      radius before fixing: 289 more N64 items fit the same shape, all
      under a handful of prolific ROM-hacker aliases (Kurko Mods ×18, Kaze
      Emanuar, GomePlayTV, Aglab2, …) invisible to the old heuristic for
      the same reason. Fixed in both `SystemGamesListCatalog
      .isReviewCandidate` (the in-app filter) and the script's
      `findReviewCandidates`: a release year past the platform's
      discontinuation is now sufficient on its own, regardless of
      publisher frequency; the rare/missing-publisher check only applies
      as a fallback when the year is missing. Spot-checked the newly-caught
      N64 items before trusting it — all 8 sampled had no PriceCharting
      listing at all, and the Banjo-Kazooie fan-hack titles correctly fall
      into "uncertain" (partial title match) rather than auto-excluding.
    - **Full `--execute` run across all 10 existing platforms, 2026-09-18**
      (first under the buggy AND-heuristic, then re-run against every
      platform under the corrected one — idempotent, re-excluding an
      already-excluded item is a no-op). Final additional exclusions from
      the corrected pass: NES 87, Atari 2600 32, SNES 215, Genesis 122,
      Game Boy 23, N64 236, PlayStation 5, Dreamcast 79, GameCube 74,
      PS2 73 — 946 more soft-deletes on top of the earlier NES/Atari 2600
      passes done before the fix. Sizable "uncertain" piles left for human
      review on every platform (partial-title-match items, never
      auto-excluded): NES 15, Atari 2600 21, SNES 39, Genesis 56,
      Game Boy 23, N64 53, PlayStation 38, Dreamcast 11, GameCube 80,
      PS2 27. A handful of PriceCharting searches (1 on Game Boy, 8 on
      N64) failed with transient HTTP 500s during the run and were treated
      as "not found" (the safer failure direction, but means a few items
      were excluded on a search failure rather than a confirmed absence —
      worth a retry-on-500 if this script gets run again).
  - **Admin surface for viewing/restoring excluded items — not started,
    not urgent, flagged 2026-09-18 for whenever admin tools come up
    again.** Right now `admin_restore_catalog_items` can only be reached
    by knowing the exact slug ahead of time (no in-app list of what's
    currently excluded, on any platform) — real friction for exactly the
    case the EU/JP region item above calls out: realizing later that a
    specific excluded title should come back. Would want at minimum a
    browsable "excluded on this platform" list (`deleted_at is not null`,
    `owner_user_id is null` — the app doesn't fetch these today since
    `SupabaseCatalogRepository` filters them out on purpose) with a
    restore action per row; natural fit alongside wherever the
    `promote_catalog_item_to_public` surface eventually lands, since both
    are "admin needs to see something the normal app deliberately hides."
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
  former. Re-swept 2026-09-18 (~35 real sites, i.e. excluding lines the
  pattern only matched incidentally): every one is either a `Task.sleep`
  cancellation (always safe to ignore), a documented fallback-to-default
  (anon key, `false`, `0`, cached data), or lenient third-party-API decoding
  — no new undocumented "didn't want to handle this" sites found.
- **Xcode's own static analyzer** (Product → Analyze, or `xcodebuild analyze`)
  catches a real class of bugs (retain cycles, unreachable code, misused
  APIs) for zero setup cost. Run for the first time 2026-09-18
  (`xcodebuild ... analyze`, iOS Simulator destination) — **clean, zero
  findings**. Cheap to re-run as an occasional manual check before a
  release, or wired into `Scripts/` alongside `leak-check.sh`, but not
  worth a standing CI step off one clean run.
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
- ~~**EU / JP region switch**~~ Plumbing built 2026-09-18 — real data still
  needs the user to run two things by hand (see below). `Region` was
  already modeled but only per-*platform* (`Platform.regionsAvailable`),
  never wired to any UI; flagged again while pruning NES bootlegs, since the
  user was excluding anything not released in NA on the explicit
  understanding some of it might need to come back once real region data
  existed.
  - **Ingest (`api/build/ingest/igdb.mjs`)**: `toItem` no longer collapses
    `release_dates.release_region` into a binary NA-or-drop decision — it
    now keeps every item and records which of NA/EU/JP it actually shipped
    in (`regions: ["NA","EU"]`, etc.), `null` when the source had no region
    data at all (treated as "assume NA" everywhere this is read, same as
    the old drop behavior for anything unconfirmed).
  - **Schema** (`supabase/schema.sql`): `catalog_items` gets a `regions
    text[]` column (`alter table ... add column if not exists`, since
    `create table if not exists` is a no-op against the already-live
    table), and `upsert_public_catalog_items` carries it through.
    **User needs to re-run this file in the Supabase SQL Editor** — no RPC
    this session has access to can run arbitrary DDL, only
    `migrate-catalog-to-supabase.mjs`'s already-defined function calls.
  - **App**: `CatalogItem.regions: [Region]?` (SwiftData, mirrors the
    `regionsAvailable`/`Region` pattern `Platform` already used),
    `FeedItem`/`SupabaseCatalogItemRow` carry it, `CatalogSyncService
    .reconcile` maps it down. New toggle in both filter menus — Browse
    Catalog (`CatalogBrowseViewModel.showNonNARegions`) and the per-system
    drill-down (`SystemGamesList`'s own `@AppStorage`, independent of the
    Browse Catalog one, matching `showHidden`'s existing precedent) — off
    by default, `regions == nil` always counts as NA regardless. Full app
    build passes.
  - **Ingest done, live DB not yet updated (checked 2026-09-19)**: every
    platform was re-ingested with `regions` (~97-100% of items per platform
    in `api/data/generated/*.json`, 21,371 of 22,003 in the built catalog),
    and the schema column exists — but a read-only check of the live table
    found `regions` null on all 16,419 public rows and far fewer rows than the
    built catalog (e.g. PlayStation 1,764 live vs 3,900 built): the last
    `migrate-catalog-to-supabase.mjs` run predates the region ingest. Until
    it's re-run, the EU/JP toggle has nothing to reveal.
  - **Second source, user's call 2026-09-18**: IGDB's region tagging is
    community-sourced and this codebase already found a gap in this exact
    field once (the old `region` property silently stopped populating —
    see `igdb.mjs`'s own comment history). Considered MobyGames (a
    purpose-built release-tracking API) but that's new integration work,
    **moved to its own backlog item below, not started**. Instead:
    `api/build/pricecharting-region-check.mjs` — cross-checks a platform's
    catalog against PriceCharting's regional console-name listings (the
    same `CONSOLE_NAMES` signal `pricecharting-catalog-match.mjs` already
    verified live per platform), report-only, doesn't write `regions`
    itself. Smoke-tested live on 3 NES items (10-Yard Fight confirmed
    NA+EU+JP, 1942 and 1943 NA-only) — correct, plausible results. User's
    reasoning for going wide rather than spot-checking: the NES/SNES/etc.
    libraries are finite and not growing, so a full per-platform pass is
    worth doing once and treating as durable. **Not run at scale yet** —
    only useful once a real re-ingest gives IGDB-derived `regions` data to
    corroborate against; reconciling the two sources is a deliberate
    separate, reviewed step, not something to auto-merge.
  - Bringing a wrongly-excluded item back in the meantime still doesn't
    need any of this — `admin_restore_catalog_items` (Phase 5) already does
    that by slug.
- **MobyGames as a second catalog-metadata source — not started, flagged
  2026-09-18** alongside the region-switch work above. A purpose-built,
  well-regarded release-tracking database with its own API; would need a
  new account/API key (the user's own, same pattern as IGDB/PriceCharting)
  and new integration code (`api/build/ingest/mobygames.mjs`-shaped, not
  started). Deferred in favor of the PriceCharting cross-check above, which
  reuses infrastructure already built and paid for this session.
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
- ~~**Sidebar navigation lag (~2s per click, macOS)**~~ **Real cause found
  2026-09-18, from a concrete new data point: the user reported it "gets
  better after visiting a few areas."** That single observation ruled out
  the leading hypothesis from the previous investigation (`RootView
  .sectionView`'s destructive `switch` fully rebuilding every screen on
  every click) as the *dominant* cause — a destructive rebuild would cost
  the same every time regardless of prior visits, not improve with
  "warm-up." The real explanation: SwiftData caches a relationship fault in
  the `ModelContext`'s identity map for the lifetime of that context, which
  (being injected once via `.modelContainer` at the app root) outlives any
  individual view's destruction/rebuild — so a *screen's* relationship-fault
  cost is genuinely one-time per platform/area, exactly matching "improves
  after a few areas." Direct measurement against the real on-disk store was
  attempted but blocked: a bundled `XCTest` can't reach the macOS app's own
  sandboxed container path (confirmed live — instant failure, not a timing
  issue), so this diagnosis rests on the already-measured 1.4-3.4s
  `SystemGamesList` cost from the earlier investigation, on finding the
  *actual* mechanism (below), and on sound, well-established SwiftData/
  CoreData fault-caching behavior, not a fresh scratch measurement.
  - **Found and fixed the dominant real cost**: `DashboardView
    .systemSummaries` and `CollectionSection.summaries` were plain,
    *uncached* computed properties — `CollectionStatsBuilder
    .systemSummaries` groups every owned/wishlisted item by platform and,
    per platform, touches that platform's full `catalogItems` relationship
    (`platform.games`/`.consoles`/`.accessories`) to compute completion
    ratios. Being a plain `var`, this re-ran on *every* SwiftUI body pass —
    not once per navigation, but potentially dozens of times while just
    sitting on Dashboard or Collection, since both are driven by an
    unscoped `@Query` that re-triggers on any `CollectionItem` change
    anywhere in the app. Exact same bug class already fixed for
    `CatalogSection.items`/`SystemGamesList.cachedCatalog`, just never
    applied here — worse here, since those two recomputed once per real
    filter change, not once per render. Fixed the same way: cached into
    `@State`, refreshed via `.task(id:)` keyed on a hash of the source
    items' `persistentModelID`s (not the filter-string-concatenation key
    the other two use, since here the *data* is what invalidates the
    cache, not a filter setting).
  - **Also moved `SystemGamesList`'s already-known 1.4-3.4s cost fully off
    the main thread** (the deferred-but-still-synchronous mitigation from
    the earlier pass only moved it past the nav animation, not off
    `@MainActor`) — new `CatalogQueryActor` (`Services/Catalog
    /CatalogQueryActor.swift`), a `@ModelActor` with its own `ModelContext`
    on the same store. `computeCatalog` itself needed no logic changes,
    just `nonisolated` (it and its helpers were implicitly `@MainActor`-
    isolated purely from being nested in a View, under this project's
    `-default-isolation=MainActor` build flag, despite never touching
    `self`) so a background actor can call it against its *own* freshly-
    fetched `Platform`. Only `PersistentIdentifier`s (`Sendable`) cross back
    to `@MainActor`, resolved to live `@Model` references there. New
    `CatalogFilterOptions` struct bundles the filter/sort settings that
    `computeCatalog`/`catalogCacheKey`/`loadCatalog`/
    `catalogItemIdentifiers` all need — added when the actor version's
    parameter list crossed `function_parameter_count`'s error threshold
    (9), and a genuine improvement on its own, not just a lint dodge, since
    all four functions wanted the identical bundle.
  - Full regression coverage: new `CatalogQueryActorTests.swift` (3 tests —
    matches the synchronous path exactly for the same inputs, respects
    search/sort, unknown platform returns empty rather than throwing).
    `SystemGamesListReviewCandidateTests` (stale before this pass — see
    "Platform expansion" section, unrelated fix landed the same session)
    and both accessibility ratchets exercised by the same screens
    (`AccessibilityAuditTests`/Dashboard, `CollectionSectionAccessibilityAuditTests`)
    all still pass. Full suite + both macOS and iOS builds clean, only the
    2 pre-existing known-by-destination-mismatch failures
    (`SidebarViewAccessibilityAuditTests` needs iPad, `AppWalkthroughTests`
    is macOS-only) remain.
- **Follow-up, 2026-09-19: lag was still noticeable, plus a concrete new
  tell — "images reload every time I switch between the sidebars."** That's
  a real, distinctive symptom of view-*identity* loss (not a data-cost
  problem — the previous pass fixed those), and it directly re-implicated
  `RootView.sectionView`'s destructive `switch`: `AsyncImage` re-runs its
  whole fetch-and-phase-transition on every fresh instantiation regardless
  of a warm `URLCache`, and a `switch` returning a different concrete type
  per `AppSection` destroys/rebuilds the entire screen (every image inside
  it included) on each click.
  - **Tried**: keeping all four sections mounted simultaneously (`ZStack` +
    `.opacity`/`.accessibilityHidden`/`.allowsHitTesting` instead of the
    `switch`), matching `tabLayout`'s existing `TabView`+`ForEach` pattern
    below (which never had this problem — `TabView` already keeps every
    tab's view alive). **Reverted** — live testing on iPad (where
    `splitLayout` actually runs; `AccessibilityAuditTests` and its siblings
    had only ever run against the iPhone/`tabLayout` destination before)
    found the other three *hidden* sections' real content — `CatalogSection`'s
    own description text, Wishlist's counts — leaking into
    `performAccessibilityAudit()` scans that should have been scoped to one
    screen (Dashboard's count jumped 11 → 71). `.accessibilityHidden`
    didn't reliably suppress it. Live Simulator inspection to tell whether
    that's a real VoiceOver-facing regression or just this audit tool
    over-scanning (this codebase has already found real cases of the
    latter — see `BreakdownBar`'s contrast-check mystery, above) wasn't
    available this session (iPad simulator device access not yet granted).
    Rather than ship a real accessibility risk on a guess, reverted to the
    plain `switch` rather than chase the a11y-tree question further.
  - **Fixed the actual reported symptom at its real source instead**: new
    `ImageMemoryCache` (`Views/Components/ImageMemoryCache.swift`, an
    `NSCache<NSURL, PlatformImage>`, in-memory only — `URLCache` already
    covers the byte-level/offline case, this is purely about smoothing
    repeat navigation within a session) + `CachedAsyncImage`
    (`Views/Components/CachedAsyncImage.swift`), a drop-in `AsyncImage`
    replacement `ItemThumbnail` now uses — checks the cache first, and a
    hit sets the image with no network round trip and no visible
    placeholder flash, even though the view itself still gets recreated on
    every switch. Narrower fix, same real payoff (no more image pop-in),
    without touching `RootView`'s architecture or its accessibility surface
    at all.
  - **Real, pre-existing gap found along the way, not caused by any of
    this**: `AccessibilityAuditTests`/`CatalogSectionAccessibilityAuditTests`/
    `CollectionSectionAccessibilityAuditTests` have never been run against
    iPad/regular-width before tonight — confirmed by re-running Dashboard's
    audit on iPad *after* the `switch` revert: still 56 findings, not 11.
    The sidebar legitimately renders alongside the detail pane on
    regular-width layout (`SidebarViewAccessibilityAuditTests`'s own doc
    comment already described this — it's *why* that test has to filter
    down to just its own `sidebar.*`-identified rows), and these three
    tests simply predate ever being pointed at a destination where that's
    true. Not fixed this pass (out of scope — a testing-coverage gap, not
    an app regression), but worth doing the same `sidebar.*`-style
    filtering for these three if they ever need to run cross-destination.
  - Full suite (iPhone) verified clean afterward — only the same 2
    known-by-destination-mismatch failures remain. Both macOS and iOS
    builds pass, lint clean.
- **Follow-up, same day: user reported it was "actually worse" after the
  above — a real pinwheel on every switch, and a specific tell: "the
  sidebar icon moves immediately, but the right pane does nothing for 2-3
  seconds."** That pins the cost to something *synchronous in the new
  screen's `body`*, before any `.task` even fires — an async-task cost
  (which is all the `ItemThumbnail`/`CachedAsyncImage` change above could
  possibly be) wouldn't block the view's first appearance like that.
  Found a second real gap in `DashboardView`, same bug class as
  `systemSummaries`, just missed the first pass: `stats` (feeding
  `statGrid`/`collectionHeader` — *always* visible, unlike
  `systemSummaries`, which only renders when the breakdown toggle is on)
  was still a plain, uncached computed property. `stats.mostValuable`
  sorts every owned item (~950 now) by `estimatedValue`, a relationship-
  touching computed property re-evaluated on every comparison, not
  memoized — done synchronously in `body` on every render. A synthetic
  in-memory timing test put the sort itself at ~160ms for 950 items, which
  alone doesn't explain 2-3s — but that test can't replicate the on-disk
  relationship-fault cost, and this project's own earlier real measurement
  of the *same class* of cost against the actual on-disk store
  (`SystemGamesList`'s `platform.catalogItems` fault, above) found 1.4-3.4s
  for a similarly-shaped operation — so real disk-backed I/O, not the sort
  algorithm, is the likely dominant factor here too. Fixed the same way as
  `systemSummaries`: cached into `@State`, refreshed alongside it in the
  same `.task(id:)` (renamed `systemSummariesCacheKey` →
  `dashboardDataCacheKey` since it now drives both). **Not yet confirmed
  fixed by the user** — full suite, lint, and both platform builds clean,
  but this needs a real re-test on the live app, not just automated
  coverage, given the previous round's fix looked clean by the same
  measures and still didn't resolve the real symptom.
  - Also found, not yet fixed: `CollectionSection.flatItems` (`CollectionListViewModel
    .apply`) has the identical `estimatedValue`-sort-comparator shape when
    its `.estimatedValue` sort field is selected — same bug class, lower
    priority since it's only reachable via the "All Games" flat toggle
    (off by default), not on by default like Dashboard's `stats`.
- **Follow-up, same day: user reported the `stats` fix was "maybe a small
  amount better" but clicking got progressively worse, then Browse Catalog
  fully locked up — "seems indicative of a memory leak."** Real bug, not a
  leak in the technical sense (nothing unreachable — `NSCache` does evict
  under pressure) but just as bad in practice: `ImageMemoryCache`'s first
  version stored whatever `CachedAsyncImage` decoded at full remote
  resolution (Wikimedia/Libretro images, commonly ~800px) for thumbnails
  actually rendered at 52-120pt, bounded only by `NSCache.countLimit`
  (object count, not memory size) — an 800×800 decoded RGBA bitmap is
  ~2.5MB, and Browse Catalog alone has 16,000+ items, so unbounded growth
  into real gigabytes was possible, worse the more distinct items' images
  you'd triggered a decode for (exactly "progressively worse"), worst on
  Catalog specifically (by far the largest item count, so the biggest
  single burst of new decodes). Fixed properly, not just patched:
  - `CachedAsyncImage.downsample` (`Views/Components/CachedAsyncImage.swift`,
    new) uses `ImageIO`/`CGImageSourceCreateThumbnailAtIndex` to decode a
    *small* bitmap directly from the compressed data at the actual display
    size (×3 for Retina, a fixed buffer rather than reading real screen
    scale) — the standard, memory-safe pattern; never fully decodes the
    large remote original at all, unlike a decode-then-resize approach.
    Runs inside `Task.detached`, off the main actor (CPU-bound synchronous
    work, would otherwise run on `@MainActor` like everything else under
    this project's `-default-isolation=MainActor` flag).
  - `ImageMemoryCache` now keys on url *and* requested pixel size (a small
    row thumbnail and a large detail-view header for the same URL are
    deliberately different cache entries — a downsampled-small bitmap
    can't be upscaled back to sharp) and tracks a real
    `NSCache.totalCostLimit` (80MB) via each entry's actual decoded byte
    size, not object count.
  - New `CachedAsyncImageTests.swift` — real PNGs (not mocks), locks down
    that an 800px synthetic image downsamples to a small pixel size and a
    correspondingly small byte cost, and that garbage data returns `nil`
    rather than crashing.
  - Full suite clean (only the 2 known-by-destination-mismatch failures),
    lint clean, both platform builds pass. **User is independently
    verifying with Instruments (Allocations)** — real profiling data, not
    just automated coverage, given how the previous two rounds each looked
    clean by every measure available here and still missed the real
    problem on the live app.
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
- ~~**Follow-up: the actual non-blocking fix (background `ModelActor`)**~~
  Done 2026-09-18 — see the sidebar-lag entry above for the full account
  (`CatalogQueryActor`). The possible catalog/collection store split below
  is still open:
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

## Platform expansion (scoped 2026-09-18) — done: all 9 ingested 2026-09-18, catalog is 19 platforms

Same shape of work as the disc-system catalogs import (PS1/PS2/Dreamcast/
GameCube, "Data feed & backend" above) — real bugs surfaced there
(non-hoisted `const` functions, the `category`/`release_region` IGDB field
bugs, duplicate-slug collisions) that a *new* platform import should expect
to hit its own version of, not assume will go smoothly just because the
pattern's proven. Deliberately sequenced *after* the PriceCharting matching
script/NES cleanup, per the user's own call.

**Scope, confirmed via direct questions rather than guessed:**
- **Floor stays at gen 2** — add ColecoVision and Intellivision alongside
  the existing Atari 2600 (all three are the same generation; Atari 2600
  alone was never meant to represent the whole era on its own).
- **Ceiling stays at gen 6 for now** — no original Xbox, no 7th gen
  (Wii/PS3/Xbox 360) yet, explicitly no 8th gen or newer (PS4/Xbox One/
  Switch/Switch 2). User's own framing: "6th for now, if any additional
  work needed to set up for success for 7th eventually, do it now" — the
  ingest script's `PLATFORMS` map (`api/build/ingest/igdb.mjs`) is already
  just a lookup table entries get added to, so there's no real structural
  prep work this implies beyond what adding these platforms already does;
  not inventing scaffolding for its own sake.
- **New platforms to add (9, bringing the catalog from 10 → 19 systems):**
  Sega Master System (gen 3, alongside NES); TurboGrafx-16/PC Engine and
  Neo Geo (gen 4, alongside SNES/Genesis — **Neo Geo explicitly lower
  priority** than the rest of this list, user's own call); Sega Saturn,
  3DO, Philips CD-i, Atari Jaguar (gen 5, alongside N64/PlayStation).
- Each one needs its own real IGDB platform-ID lookup and ingest run
  (`igdb.mjs`), the same as every platform already in the catalog — the
  user's own IGDB credentials are required for this (not held by the
  assistant; every real IGDB check this project has done has gone through
  the user running the actual query and sharing results back). Platforms
  themselves stay bundled/local-only either way (`api/data/curated.json`,
  never migrated to Supabase — see "Catalog goes live in Supabase"'s Phase
  2 section for why) — the app's own `Platform` list is fully data-driven
  from whatever's in the feed, so no client-side model/UI change is needed
  just to add a platform; only the ingest + migration pipeline is real
  work here.
- **Done 2026-09-18**: all 9 added to `api/data/curated.json` (discontinued/
  release years, generation, manufacturer, icon, summary — same shape as
  the original 10), full local build (`api/build/build.mjs`) confirmed
  clean at 19 platforms. Web search for the 9 numeric IGDB platform ids
  turned up genuinely conflicting numbers for Sega Saturn and Atari Jaguar
  across different sources — rather than trust either, `igdb.mjs` now
  resolves these 9 live by exact platform name (`PLATFORMS_BY_NAME` +
  `resolvePlatformId`, one extra `/platforms` lookup per run, erroring
  loudly on zero or multiple matches) instead of a hardcoded id, so a wrong
  guess can't silently pull an entirely different platform's games — names
  confirmed against igdb.com/platforms's own listing, not guessed. Existing
  10 platforms keep their already-verified hardcoded ids unchanged.
- **Done (ingested 2026-09-18; kept for the how-to)**: the actual ingest run needs `IGDB_CLIENT_ID`/
  `IGDB_CLIENT_SECRET` (create an app at
  https://dev.twitch.tv/console/apps, per `igdb.mjs`'s own header comment)
  — not held by this session. Once set:
  `IGDB_CLIENT_ID=… IGDB_CLIENT_SECRET=… node api/build/ingest/igdb.mjs colecovision intellivision sega-master-system turbografx-16 neo-geo saturn 3do cd-i jaguar`
  (or with no platform args, re-runs *every* platform including the
  original 10 — safe/idempotent, but slower). Then `node api/build/build.mjs`
  and `SUPABASE_SERVICE_ROLE_KEY=… node api/build/migrate-catalog-to-supabase.mjs`
  to push the result live, same pipeline every platform already goes
  through. Whether each of these 9 needs its own hand-curated seed items
  (hardware, notable variants) the way the original 10 did, or can lean
  more heavily on IGDB's own data from the start, is still open.
- **Real regression, found and fixed 2026-09-18, same day the 9-platform
  ingest first ran for real**: the user ran the 10-original-platform
  region-data re-ingest above, then reported it "imported all the games we
  removed previously." Root cause: `upsert_public_catalog_items`'s `ON
  CONFLICT ... DO UPDATE` unconditionally reset `deleted_at = null` on
  every re-synced slug ("a re-synced item should never stay tombstoned") —
  written before the admin-exclude feature existed, so it had no way to
  tell "reappeared legitimately" apart from "an admin deliberately excluded
  this and a routine ingest re-run knows nothing about that." Confirmed
  live: `n64-15` (the very item that started the review-candidate heuristic
  investigation) was back with `deleted_at: null`. Fixed by removing that
  reset entirely — `admin_restore_catalog_items`, by explicit slug, is now
  the only path that clears it server-side. **User needs to re-run
  `schema.sql` in the SQL Editor once more** to pick up the corrected
  function. Recovery: `api/build/restore-pricecharting-exclusions.mjs`
  (new) re-applied the 946 exclusions the most recent report files on disk
  recorded, zero PriceCharting API calls needed — but those reports only
  reflect each platform's *last* run, and several platforms had an earlier
  pass too (Genesis/Game Boy/N64/PlayStation/Dreamcast/GameCube/PS2 were
  first swept under the pre-fix heuristic, found more later under the
  corrected one) whose results were never saved anywhere the report files
  still hold, so a full `pricecharting-catalog-match.mjs --execute` pass
  was also re-kicked off across all 10 platforms to catch whatever the
  partial restore missed. **Worth remembering**: any future re-ingest is
  now safe by construction (the reset is gone), but if this ever needs
  auditing again, the "assume the freshest report file has everything"
  shortcut is specifically not always true — check the platform's full
  history in this file, not just the file on disk from its most recent run.
  **Fully resolved**: the partial-restore theory was confirmed correct —
  the follow-up full `--execute` pass (computed fresh against the
  regression's fully-resurrected live catalog, so it necessarily captured
  every historical exclusion in one pass, not just the last report's) found
  and re-excluded far more than the 946 the report-based restore alone
  caught: NES 415, Atari 2600 160, SNES 552, Genesis 260, Game Boy 332,
  N64 315, PlayStation 133 (2,167 more on top of the 946 already restored —
  2,634 combined for the evening's full recovery, though these two figures
  overlap somewhat since the second pass necessarily re-touched everything
  the first already fixed). Dreamcast/GameCube/PS2 needed nothing further
  in this pass — apparently no earlier-pass gap existed for those three.
  Verified live: `n64-15` (the item that started this whole investigation)
  carries a fresh `deleted_at` again.

## RetroGameCollector import (2026-09-18) — done

User's existing collection lived on a third-party site
(my.puregaming.org/RetroGameCollector) — public, no-login collection view,
paginated per-system. Scraped (`export_rgc_collection.py`, session
scratchpad, not committed — one-off) rather than clicked through 30+
systems by hand: 1,376 owned items across 33 RGC systems.

- Scope: only the 10 platforms RetroStacks already supported at the time
  (1,006 of the 1,376 items) — user's own call, matching the earlier
  scoping decision to skip handhelds/Xbox/post-PS2 PlayStation/Switch
  entirely and to wait on the (then-unbuilt) 9-platform expansion above
  rather than import placeholder data for it. The other 370 are kept in the
  scratchpad CSV for whenever those platforms get real ingest.
- `api/build/rgc-collection-import.mjs`: matches by normalized title
  (exact, numeral-variant — "2" ↔ "II", a real and common NES/SNES sequel-
  naming mismatch — unique base-title, then a directional word-subset
  fallback for publisher-prefix/subtitle differences like "DuckTales" →
  "Disney's DuckTales"). The word-subset tier was checked both directions
  before trusting it — the reverse direction (catalog words ⊆ RGC words)
  looked right for stripping RGC's own "Round Seal" noise but live-matched
  real sequels onto their unrelated base game ("Back to the Future 2 & 3" →
  "Back to the Future", "Gauntlet 2" → "Gauntlet") since a short title is
  trivially a subset of almost anything sharing its words — dropped
  entirely rather than patched further. A second live catch: a catalog
  match whose only "extra" word was a bare sequel number
  ("Infiltrator" → "Infiltrator II") is real risk, not noise — those are
  known distinct games — so that shape gets deferred to "ambiguous" instead
  of auto-matched, same posture as every other real-vs-guessed judgment
  call this session. Wrote 945 `collection_items` rows + 92 new private
  `catalog_items` (things the shared catalog didn't have — mostly "Round
  Seal"/variant carts). 16 genuinely ambiguous titles and 42 items that
  read as hardware, not games (RGC doesn't distinguish kind), left for a
  human/handled separately rather than guessed.
- **Real duplicate-import bug, found from the user's own "check the N64
  list" prompt, not caught beforehand**: RGC lists Player's Choice/5-screw
  reprint variants as separate rows ("GoldenEye 007" and "GoldenEye 007
  (Player's Choice)"), but the catalog only has one slug for the base game
  — both rows resolved to the same `catalog_slug`, and the import's own
  dedup check only compared against collection rows that existed *before*
  the run started, not against other rows created earlier in the *same*
  run. 47 duplicate pairs (23 NES, 24 N64) — fixed by tombstoning the
  worse-completeness copy of each pair (`deleted_at`, not a hard delete —
  matches the app's own soft-delete convention, and a bulk hard-delete was
  in fact blocked by this environment's own safety classifier). Worth
  remembering for any future bulk-collection-import work: dedup against
  the batch being written, not just against what already existed.
- `api/build/rgc-hardware-import.mjs`: the 42 hardware items, by hand — 12
  matched existing console/accessory catalog entries (verified against the
  live catalog, not guessed), 28 became new private `catalog_items` with
  real `kind` (console/accessory), 2 turned out to be misfiled games (a
  reissue variant and a punctuation-tokenization miss on an existing game)
  and were routed back to their real catalog entries instead.

## Sidebar-switch lag: findings from a live `sample` (2026-09-19)

Memory was flat (~190-210MB), so not a leak. A 30s main-thread `sample` while
clicking showed ~5.6s of SwiftUI layout stalls driven by `CollectionSection`:
- `fileExporter(document:)` args were rebuilt every `body` pass (full JSON archive + CSV) -> now lazy via `CollectionExport`, guarded by `CollectionExportTests`.
- `systemSummaries` ran `isHidden` (expensive persisted getter) over ~16k catalog items in several passes on main -> single pass, now computed off-main by `CollectionSummariesActor`.
- Still open: `DashboardView` `CollectionStatsBuilder.build` runs on main; `CollectionSection.flatItems` `estimatedValue` sort (All Games); `RootView` switch identity loss. Re-sample after the next build to see what's left.

### Lag — status after the 2026-09-19 session (low priority now)
Fixed: exporter docs built every render; `@ModelActor`s were running on main (now built via `@concurrent` helpers); Catalog browse filter/sort off-main (`CatalogBrowseFilter`); shared stale-while-revalidate caches (`SystemSummariesCache`, `PlatformOverviewCache`) invalidated on sync/hide; image cache byte-budgeted.
Remaining ideas, all minor:
- First visit after launch still pays ~1-2s for summaries (faults every catalog item per owned platform). Cheaper: SQL `fetchCount` per platform/kind instead of loading items; or warm the cache at launch.
- `DashboardView` `CollectionStatsBuilder.build` still runs on main (fast enough now).
- `CollectionSection.flatItems` `estimatedValue` sort on All Games.
- Opening a platform / Catalog search+filter still uses the background filter over the full catalog fetch; could push predicates into the fetch.
- Catalog no longer live-refreshes on sync while a filtered list is open (updates on next filter change).
- `RootView` destructive `switch` loses view identity on every sidebar switch (keep-alive attempt broke the accessibility audit).
- Debug builds are much slower than Release for SwiftData getters — measure a Release build before chasing more.
