# Supabase (Phase 1 — multi-device collection sync)

Not wired up yet. This is the plan + the schema, ready for when the project exists.
See the root [`BACKLOG.md`](../BACKLOG.md#multi-user-phase-1) for how this fits
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

## Setup (your side)

1. **Create a project** at [supabase.com](https://supabase.com) — free tier is
   plenty for a solo user (500 MB DB, 1 GB storage, 50k monthly active users).
2. **Run the schema**: Dashboard → SQL Editor → New query → paste all of
   [`schema.sql`](schema.sql) → Run. Creates `collection_items` +
   `collection_item_photos`, a private `collection-photos` storage bucket, and
   RLS policies scoping every row/object to `auth.uid()`.
3. **Turn on email auth** (usually on by default): Dashboard → Authentication →
   Providers → Email. Magic link / OTP, not password — matches
   `AccountService.sendMagicLink(to:)`'s existing shape.
4. **Grab the project URL and anon (public) key**: Dashboard → Project Settings
   → API. The anon key is safe to ship in the app — RLS is what actually
   protects the data, not the key being secret.
5. Hand those two values back and the client-side wiring (below) happens next.

## What I'll build once the project exists

Both seams already exist in the code, built during Phase 0 specifically so this
would be a drop-in, not a redesign:

- **`AccountService`** (`Services/Sync/AccountService.swift`) — currently always
  `.signedOut`; `sendMagicLink` throws `.notConfigured`. Gets real Supabase Auth
  calls (REST, no SDK needed — `POST /auth/v1/otp` to send the link, a custom
  URL scheme to catch the callback and exchange it for a session).
- **`Sync.engine`** (`Services/Sync/CollectionSyncEngine.swift`) — one line,
  `DisabledSyncEngine()` → `SupabaseCollectionSyncEngine()`. Implements
  `pull(since:)` (`GET /rest/v1/collection_items?user_id=eq.…&updated_at=gt.…`)
  and `push(_:)` (`POST .../collection_items` upsert), trading in
  `CollectionChange` — which already reuses `CollectionArchive.Entry` as its row
  shape, so there's one serialization to maintain, not two.
- **A sync coordinator**: last-write-wins by `CollectionItem.updatedAt`
  (already ticked by `touch()` on every local edit — see `CollectionItem.swift`),
  tombstones (`deletedAt`) carry deletes both ways, runs on sign-in / app
  foreground / a manual "Sync now".
- **`AppStatusCenter.report(.collectionSync, …)`** — a failed push/pull shows in
  the same corner badge as catalog sync, not a new UI pattern.
- **Photos**: `CollectionItem.photoData` uploads to the `collection-photos`
  bucket instead of inlining base64 (that's fine for the local JSON export, not
  for a synced row) — path `<user_id>/<exportID>/<n>.jpg`, RLS'd by folder.
- **Magic-link sign-in sheet** — email field, "Check your mail," deep-link
  callback handling.

**Why this waits for a live project:** auth flows and RLS policies are the kind
of thing that's cheap to get subtly wrong and expensive to debug blind — I want
to exercise a real magic-link round trip and a real `auth.uid()` against the
policies above before it touches your collection, not guess at the REST
response shapes from documentation. The schema and this plan are written now so
setup → wiring is a short loop once you're ready, not a redesign.

## Later: `sources/supabase.mjs`

Separate from the above — a *build-time* option, not app-time. Right now
`api/build/build.mjs` reads the catalog from `api/data/curated.json` +
`generated/*.json` (`SOURCE=local-file`, the default). If the catalog ever
outgrows hand-maintained JSON files, `api/build/sources/supabase.mjs` (skeleton
already there) would let the *feed* be generated from a Supabase table instead —
a completely separate concern from collection sync above, and not needed yet at
~3,600 items.

## Later: companion website

`retrostacks.com` — a read-only (then editable) mirror of the collection, same
schema, Supabase's JS client. Comes after the app-side sync is solid.
