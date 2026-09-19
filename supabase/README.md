# Supabase (collection sync + the shared catalog)

**Collection sync wired up and live** (2026-09-12); **the catalog moved into
Supabase 2026-09-17** (see *The catalog* below). This doc describes what's
actually built. See
[`FEATURES.md`](../FEATURES.md#multi-user-sync-supabase-phase-1) for the
history (including the bugs the live sign-in test found) and
[`BACKLOG.md`](../BACKLOG.md) for what's still pending (Photos upload).

## What this is for

Today the collection lives only in this device's local SwiftData store; the only
way to move it is a manual JSON export/import (`CollectionArchive`, no iCloud —
see `api/README.md`). Supabase adds **optional** multi-device sync: sign in with
an email magic link, and the same collection follows you to another device.
Nothing about the local-first behavior changes — signed out is still a fully
functional mode.

**Scope check:** two separate concerns share this project. *Collection sync*
holds only your personal collection (ownership, condition, notes, photos), in
`collection_items` / `collection_item_photos`, RLS-scoped to `auth.uid()`. The
*catalog* (`catalog_items`) is reference data: public rows (`owner_user_id`
null) readable by everyone, plus a user's own private custom rows.

## Setup (done — for reference)

1. **Project created** at [supabase.com](https://supabase.com) — free tier
   (500 MB DB, 1 GB storage, 50k monthly active users), plenty for a solo user.
2. **Schema applied**: [`schema.sql`](schema.sql) run via Dashboard → SQL
   Editor (idempotent — re-run it whenever the file changes). Creates
   `collection_items` + `collection_item_photos`, a private `collection-photos`
   storage bucket, RLS policies scoping every row/object to `auth.uid()`, and
   the catalog objects described below.
3. **Email auth on**: Dashboard → Authentication → Providers → Email. Magic
   link, not password — matches `AccountService.sendMagicLink(to:)`.
4. **Project URL + publishable (anon) key** are in `SupabaseConfig.swift` — safe
   to ship in the app, RLS is what actually protects the data, not the key being
   secret. The **service-role key** is different: it bypasses RLS, lives only in
   the gitignored `api/.env`, and is used only by the `api/build/*` scripts.

## What's built

Both seams below were built during Phase 0 (before the project existed)
specifically so wiring in a real project would be a drop-in, not a redesign —
and that's how it went:

- **`AccountService`** (`Services/Sync/AccountService.swift`) — real Supabase
  Auth calls over raw REST (no SDK, to avoid any Xcode project/package-manager
  changes): `POST /auth/v1/otp` sends the magic link. The callback is **not**
  a URL-scheme deep link — that would've meant an Info.plist/target change,
  off-limits per `CLAUDE.md`'s guardrails — instead the user pastes the link
  text back into the app (`SignInSheet`), and `SupabaseAuthClient` extracts
  the token from it and exchanges it for a session via `/auth/v1/verify`.
- **`Sync.engine`** (`Services/Sync/CollectionSyncEngine.swift`) — points at
  `SupabaseCollectionSyncEngine()`. Implements `pull(since:)`
  (`GET /rest/v1/collection_items?user_id=eq.…&updated_at=gt.…`) and
  `push(_:)` (`POST .../collection_items` upsert), trading in
  `CollectionChange` — which reuses `CollectionArchive.Entry` as its row
  shape, so there's one serialization to maintain, not two.
  `DisabledSyncEngine` stays in the same file as the local-first fallback
  shape and for tests that don't want real network/Keychain calls.
- **`SyncCoordinator`**: last-write-wins by `CollectionItem.updatedAt`
  (ticked by `touch()` on every local edit), tombstones (`deletedAt`) carry
  deletes both ways, runs on sign-in / app foreground / a manual "Sync now".
- **`AppStatusCenter.report(.collectionSync, …)`** — a failed push/pull shows
  in the same corner badge as catalog sync, not a new UI pattern.
- **Magic-link sign-in sheet** (`Views/Account/SignInSheet.swift`) — email
  field, "Check your mail," a field to paste the link back in.
- **Regression-tested**: `AccountServiceTests` (Keychain session round-trip —
  this is what caught a real silent bug where session persistence was
  completely broken, see `FEATURES.md`), `SupabaseCollectionRowTests` (wire
  format), `SyncCoordinatorTests` (merge logic). Not something to take on
  faith — see `FEATURES.md`'s Multi-user section for the actual bugs found
  this way.

**Not done yet**: **Photos** — `CollectionItem.photoData` still doesn't sync;
it needs the Storage bucket upload (`collection-photos`, already created by
`schema.sql`, path `<user_id>/<exportID>/<n>.jpg`) wired into
`SupabaseCollectionSyncEngine` or a sibling type. Every other field syncs
without it.

**Live sign-in has been exercised** (2026-09-15/16): a real magic-link round
trip against the real project, which found a real bug the unit tests couldn't
(`completeSignIn` posted the wrong `/verify` body shape — see FEATURES.md).

## The catalog (`catalog_items`)

- **One table, split by owner**: `owner_user_id is null` = public/shared,
  otherwise private to that user (custom entries, e.g. a variant the catalog
  lacks). Users can only write their own rows.
- **Loading it**: `node api/build/migrate-catalog-to-supabase.mjs` (service-role
  key) upserts the built catalog through `upsert_public_catalog_items(jsonb)` —
  a `SECURITY DEFINER` function, `service_role` only (PostgREST's own upsert
  can't target the partial unique index). It preserves `deleted_at`, so a
  re-sync never un-excludes an item.
- **Admin curation**: an `admins` table plus `is_admin()`,
  `admin_exclude_catalog_items(slugs)` / `admin_restore_catalog_items(slugs)`
  (soft-delete via `deleted_at`, tombstones sync to every device) and
  `promote_catalog_item_to_public()`. These check `auth.uid()`, so they only work
  as a signed-in admin — not with the service-role key (use a direct `PATCH` of
  `deleted_at` for scripts).
- **App side**: `SupabaseCatalogRepository` pages the item rows into
  `CatalogFeed` (the *platform* list is not in Supabase — it comes from the
  bundled `CatalogSeed.json`, synced from `curated.json`); `CatalogSyncService`
  upserts both into SwiftData. Items carry
  `regions`; the app filters to North America by default.

Still available but unused: `api/build/sources/supabase.mjs` (a skeleton for
building the *static* feed from this table instead of from JSON files).

## Later: companion website

`retrostacks.com` — a read-only (then editable) mirror of the collection, same
schema, Supabase's JS client. Comes after the app-side sync is solid.
