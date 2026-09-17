-- RetroStacks — Supabase schema.
--
-- Run this once in the Supabase project's SQL Editor (Dashboard → SQL Editor →
-- New query → paste → Run). Idempotent — safe to re-run.
--
-- Phase 1 (below): the user's personal collection data (CollectionItem). A
-- collection row references a catalog entry by its slug (`catalog_slug`),
-- not a live foreign key — originally because the catalog lived outside this
-- database entirely (a static JSON feed at data.retrostacks.com); now that
-- Phase 2 (catalog_items, further down) moved the catalog into Postgres too,
-- it stays a loose slug reference anyway, since a local device's collection
-- row can reference a catalog item it hasn't pulled down yet.
--
-- Row shape mirrors apple/RetroStacks/Services/Collection/CollectionArchive.swift
-- (`CollectionArchive.Entry`) — the same fields as the local JSON export, so the
-- sync engine and the file-based backup share one mental model.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.collection_items (
  -- CollectionItem.exportID — the client already mints this locally and it's
  -- stable across export/import, so it's the primary key here too (no server
  -- ID translation needed on either side).
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,

  catalog_slug text,                 -- references the static catalog feed, not a local FK
  status text not null,              -- CollectionStatus.rawValue
  condition text,                    -- ConditionGrade.rawValue
  completeness text,                 -- Completeness.rawValue
  has_box boolean not null default false,
  has_manual boolean not null default false,
  has_inserts boolean not null default false,
  has_original_packaging boolean not null default false,
  grading_company text not null default 'none',
  grade_score double precision,
  price_paid numeric(10, 2),
  date_acquired timestamptz,
  acquisition_source text,
  estimated_value_override numeric(10, 2),
  storage_location text,
  notes text not null default '',
  play_status text,
  date_added timestamptz not null,

  -- Sync bookkeeping — mirrors CollectionItem.updatedAt / deletedAt.
  updated_at timestamptz not null default now(),
  deleted_at timestamptz             -- tombstone; null = live
);

-- Photos deliberately are NOT inlined as base64 here the way the local JSON
-- archive does (CollectionArchive.Entry.photosBase64) — that's fine for a
-- portable file, but bloats table/row size and WAL churn in Postgres. Use a
-- Supabase Storage bucket per user instead (`storage.objects`, path prefixed
-- by `user_id`) and keep just the object paths:
create table if not exists public.collection_item_photos (
  collection_item_id uuid not null references public.collection_items (id) on delete cascade,
  storage_path text not null,
  position smallint not null default 0,
  primary key (collection_item_id, storage_path)
);

-- ---------------------------------------------------------------------------
-- Indexes — both queries the sync engine actually makes
-- ---------------------------------------------------------------------------

-- pull(since:): "everything for this user changed after X" (deleted_at included,
-- so tombstones come back too).
create index if not exists collection_items_user_updated_idx
  on public.collection_items (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- updated_at bookkeeping
-- ---------------------------------------------------------------------------
-- Belt-and-suspenders: the client sets updated_at itself (it's the
-- last-write-wins clock), but force it forward on every UPDATE too, in case a
-- future admin tool or trigger writes a row without setting it explicitly.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = greatest(new.updated_at, now());
  return new;
end;
$$;

drop trigger if exists collection_items_touch_updated_at on public.collection_items;
create trigger collection_items_touch_updated_at
  before update on public.collection_items
  for each row
  execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row-Level Security — a user can only ever see/write their own rows
-- ---------------------------------------------------------------------------

alter table public.collection_items enable row level security;
alter table public.collection_item_photos enable row level security;

drop policy if exists "collection_items_select_own" on public.collection_items;
create policy "collection_items_select_own"
  on public.collection_items for select
  using (auth.uid() = user_id);

drop policy if exists "collection_items_insert_own" on public.collection_items;
create policy "collection_items_insert_own"
  on public.collection_items for insert
  with check (auth.uid() = user_id);

drop policy if exists "collection_items_update_own" on public.collection_items;
create policy "collection_items_update_own"
  on public.collection_items for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- No delete policy on purpose: deletes are soft (deleted_at), done via UPDATE,
-- so tombstones can propagate to other devices before ever disappearing.

drop policy if exists "collection_item_photos_all_own" on public.collection_item_photos;
create policy "collection_item_photos_all_own"
  on public.collection_item_photos for all
  using (
    exists (
      select 1 from public.collection_items ci
      where ci.id = collection_item_id and ci.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.collection_items ci
      where ci.id = collection_item_id and ci.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Storage bucket for photos (private; RLS'd by path prefix = user id)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('collection-photos', 'collection-photos', false)
on conflict (id) do nothing;

drop policy if exists "collection_photos_own_folder" on storage.objects;
create policy "collection_photos_own_folder"
  on storage.objects for all
  using (
    bucket_id = 'collection-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'collection-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =============================================================================
-- Phase 2 (2026-09-17): the reference catalog itself, live in Postgres.
--
-- Until now the catalog (platforms/games/prices) was a static JSON feed built
-- by api/build/*.mjs and downloaded read-only — see the note this replaces at
-- the top of this file. That still generates the data (igdb.mjs/curated.json/
-- build.mjs are unchanged); only the *last step* changes, from "write a JSON
-- file" to "upsert into catalog_items as public rows" via the service-role
-- key from a privileged script, never the app itself.
--
-- One table, split by ownership, not two parallel systems:
--   owner_user_id IS NULL  → public/shared, visible to everyone
--   owner_user_id = <uid>  → private, visible only to that user
-- A regular user (via the anon key + their own JWT) can only ever insert,
-- update, or delete rows where owner_user_id = auth.uid() — never a public
-- row directly, not even their own submissions. Publishing something to the
-- public catalog is a separate, admin-gated action (promote_catalog_item_to
-- _public below), not a normal write.
--
-- Platforms are NOT part of this migration — still the small, stable, bundled
-- set the app already ships with. catalog_items references a platform by
-- platform_slug (a loose string reference, same pattern collection_items
-- already uses for catalog_slug), not a live foreign key into a table that
-- doesn't exist here. Revisit only if custom platforms are ever actually
-- wanted — nothing requested so far needs it.
-- =============================================================================

create table if not exists public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  owner_user_id uuid references auth.users (id) on delete cascade,  -- null = public

  platform_slug text not null,
  kind text not null,                -- ItemKind.rawValue
  name text not null,
  variant text,
  release_year_na integer,
  manufacturer_or_publisher text,
  developer text,
  genre text,
  upc text,
  summary text not null default '',

  image_name text,
  image_url_string text,
  image_credit text,
  image_license text,

  estimated_value_loose numeric(10, 2),
  estimated_value_complete numeric(10, 2),
  estimated_value_sealed numeric(10, 2),
  estimated_value_graded numeric(10, 2),
  sales_volume_yearly integer,
  price_guide_provider_id text,
  price_guide_updated_at timestamptz,

  -- Set by the row's own owner on their private row ("I'd like this folded
  -- into the shared catalog"); only promote_catalog_item_to_public can ever
  -- actually act on it — see below.
  submitted_for_public boolean not null default false,

  updated_at timestamptz not null default now(),
  deleted_at timestamptz             -- tombstone; null = live (same reasoning as collection_items)
);

-- Postgres treats NULL as distinct from every other NULL in a unique
-- constraint, so a plain `unique (slug, owner_user_id)` would silently allow
-- unlimited duplicate *public* slugs (every public row has owner_user_id =
-- null). Two partial indexes instead: public slugs unique among themselves,
-- private slugs unique per-owner (two different users can each have their
-- own "my-bootleg-cart" without colliding).
create unique index if not exists catalog_items_public_slug_idx
  on public.catalog_items (slug) where owner_user_id is null;
create unique index if not exists catalog_items_private_slug_idx
  on public.catalog_items (slug, owner_user_id) where owner_user_id is not null;

create index if not exists catalog_items_owner_updated_idx
  on public.catalog_items (owner_user_id, updated_at);
create index if not exists catalog_items_platform_idx
  on public.catalog_items (platform_slug);

drop trigger if exists catalog_items_touch_updated_at on public.catalog_items;
create trigger catalog_items_touch_updated_at
  before update on public.catalog_items
  for each row
  execute function public.touch_updated_at();

alter table public.catalog_items enable row level security;

drop policy if exists "catalog_items_select" on public.catalog_items;
create policy "catalog_items_select"
  on public.catalog_items for select
  using (owner_user_id is null or owner_user_id = auth.uid());

drop policy if exists "catalog_items_insert_own" on public.catalog_items;
create policy "catalog_items_insert_own"
  on public.catalog_items for insert
  with check (owner_user_id = auth.uid());

drop policy if exists "catalog_items_update_own" on public.catalog_items;
create policy "catalog_items_update_own"
  on public.catalog_items for update
  using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid());

-- No delete policy on purpose, same reasoning as collection_items: deletes
-- are soft (deleted_at via UPDATE), so a removal can propagate to your other
-- devices before the row actually disappears.

-- ---------------------------------------------------------------------------
-- Admins — who can promote a private submission to the public catalog.
-- ---------------------------------------------------------------------------
-- No SELECT/INSERT/UPDATE policies at all on this table: nobody can read or
-- write it through the anon key/REST API, admin or not. Membership is
-- managed by hand in the SQL Editor. The only thing that ever reads it is
-- the SECURITY DEFINER function below, which runs with elevated privilege
-- internally regardless of RLS.

create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.admins enable row level security;

-- Add yourself once, by hand, after running this file:
--   insert into public.admins (user_id) values ('<your auth.users.id>');

create or replace function public.promote_catalog_item_to_public(item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'not authorized';
  end if;
  update public.catalog_items
  set owner_user_id = null, submitted_for_public = false
  where id = item_id;
end;
$$;

-- Callable from the app via Supabase's RPC endpoint:
--   POST /rest/v1/rpc/promote_catalog_item_to_public  { "item_id": "<uuid>" }
-- Not wired into the app yet — Phase 5 (an admin surface, likely on the
-- future companion website, not worth a whole in-app UI for a single-admin
-- action).

-- ---------------------------------------------------------------------------
-- Bulk upsert for the migration/refresh script — service_role only.
-- ---------------------------------------------------------------------------
-- Found live 2026-09-17: PostgREST's own upsert (`Prefer: resolution=
-- merge-duplicates` + `?on_conflict=slug`) generates a plain
-- `ON CONFLICT (slug) DO UPDATE`, which Postgres rejects (42P10, "no unique
-- or exclusion constraint matching") against catalog_items_public_slug_idx,
-- since that's a *partial* index (`WHERE owner_user_id IS NULL`) — an
-- ON CONFLICT target has to match a real index's exact shape, predicate
-- included, and PostgREST's on_conflict param can't express one. Confirmed
-- by actually trying it against the real table before writing this, not
-- assumed. A hand-written function with the real `ON CONFLICT (slug) WHERE
-- owner_user_id IS NULL DO UPDATE ...` is the only way to hit that index.
--
-- Takes a JSONB array so one call upserts a whole batch, not one row per
-- HTTP request — the migration script batches a few hundred/thousand items
-- per call. Explicitly locked to service_role: without the revoke below,
-- *any* authenticated user (even just the anon key) could call this RPC and
-- write directly into the public catalog, which is exactly what the insert
-- RLS policy on catalog_items exists to prevent for normal table writes.

create or replace function public.upsert_public_catalog_items(items jsonb)
returns void
language plpgsql
as $$
begin
  insert into public.catalog_items (
    slug, owner_user_id, platform_slug, kind, name, variant, release_year_na,
    manufacturer_or_publisher, developer, genre, upc, summary,
    image_name, image_url_string, image_credit, image_license
  )
  select
    item ->> 'slug',
    null,
    item ->> 'platform_slug',
    item ->> 'kind',
    item ->> 'name',
    item ->> 'variant',
    nullif(item ->> 'release_year_na', '')::integer,
    item ->> 'manufacturer_or_publisher',
    item ->> 'developer',
    item ->> 'genre',
    item ->> 'upc',
    coalesce(item ->> 'summary', ''),
    item ->> 'image_name',
    item ->> 'image_url_string',
    item ->> 'image_credit',
    item ->> 'image_license'
  from jsonb_array_elements(items) as item
  on conflict (slug) where owner_user_id is null
  do update set
    platform_slug = excluded.platform_slug,
    kind = excluded.kind,
    name = excluded.name,
    variant = excluded.variant,
    release_year_na = excluded.release_year_na,
    manufacturer_or_publisher = excluded.manufacturer_or_publisher,
    developer = excluded.developer,
    genre = excluded.genre,
    upc = excluded.upc,
    summary = excluded.summary,
    image_name = excluded.image_name,
    image_url_string = excluded.image_url_string,
    image_credit = excluded.image_credit,
    image_license = excluded.image_license,
    deleted_at = null;  -- a re-synced item should never stay tombstoned
end;
$$;

revoke execute on function public.upsert_public_catalog_items(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_public_catalog_items(jsonb) to service_role;
