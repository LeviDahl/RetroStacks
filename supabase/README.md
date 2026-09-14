# Supabase (Phase 1 — multi-device collection sync)

**Wired up and live** (2026-09-12). This doc originally described the plan
before the project existed; it now describes what's actually built. See the
root [`BACKLOG.md`](../BACKLOG.md#multi-user-phase-1) for what's still
pending (a real end-to-end sign-in test, Photos upload) and how this fits
the rest of the roadmap.

## What this is for

Today the collection lives only in this device's local SwiftData store; the only
way to move it is a manual JSON export/import (`CollectionArchive`, no iCloud —
see `api/README.md`). Supabase adds **optional** multi-device sync: sign in with
an email magic link, and the same collection follows you to another device.
Nothing about the local-first behavior changes — signed out is still a fully
functional mode.

**Scope check:** Supabase only ever holds *your personal collection* (ownership,
condition, notes, photos) — never the reference catalog. The catalog stays the
free static JSON feed at `data.retrostacks.com`; Supabase and that feed don't
know about each other.

## Setup (done — for reference)

1. **Project created** at [supabase.com](https://supabase.com) — free tier
   (500 MB DB, 1 GB storage, 50k monthly active users), plenty for a solo user.
2. **Schema applied**: [`schema.sql`](schema.sql) run via Dashboard → SQL
   Editor. Created `collection_items` + `collection_item_photos`, a private
   `collection-photos` storage bucket, and RLS policies scoping every
   row/object to `auth.uid()`.
3. **Email auth on**: Dashboard → Authentication → Providers → Email. Magic
   link, not password — matches `AccountService.sendMagicLink(to:)`.
4. **Project URL + anon (public) key** are in `SupabaseConfig.swift` — the
   anon key is safe to ship in the app, RLS is what actually protects the
   data, not the key being secret.

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
  completely broken, see `BACKLOG.md`), `SupabaseCollectionRowTests` (wire
  format), `SyncCoordinatorTests` (merge logic). Not something to take on
  faith — see `BACKLOG.md`'s Multi-user section for the actual bugs found
  this way.

**Not done yet**: **Photos** — `CollectionItem.photoData` still doesn't sync;
it needs the Storage bucket upload (`collection-photos`, already created by
`schema.sql`, path `<user_id>/<exportID>/<n>.jpg`) wired into
`SupabaseCollectionSyncEngine` or a sibling type. Every other field syncs
without it. Also still pending: a real, live end-to-end sign-in test — send
an actual email, paste an actual link back, watch a real row land in
`collection_items`. Everything up to that point is real-Keychain and
real-wire-format tested, but nobody has done the live round trip yet.

**Why the live sign-in test still matters:** auth flows and RLS policies are
the kind of thing that's cheap to get subtly wrong and expensive to debug
blind. Everything that unit tests can cover (Keychain persistence, wire
format, merge logic) already found and fixed one real bug this way — but a
real magic-link round trip and a real `auth.uid()` against the RLS policies
above needs an actual email sent and an actual link pasted back, not another
guess at the REST response shape. That's the one remaining gap between
"built and tested" and "trust it with your real collection."

## Later: `sources/supabase.mjs`

Separate from the above — a *build-time* option, not app-time. Right now
`api/build/build.mjs` reads the catalog from `api/data/curated.json` +
`generated/*.json` (`SOURCE=local-file`, the default). If the catalog ever
outgrows hand-maintained JSON files, `api/build/sources/supabase.mjs` (skeleton
already there) would let the *feed* be generated from a Supabase table instead —
a completely separate concern from collection sync above, and not needed yet at
~13,000 items.

## Later: companion website

`retrostacks.com` — a read-only (then editable) mirror of the collection, same
schema, Supabase's JS client. Comes after the app-side sync is solid.
