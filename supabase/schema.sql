-- RetroStacks — Supabase schema for Phase 1 (multi-device collection sync).
--
-- Run this once in the Supabase project's SQL Editor (Dashboard → SQL Editor →
-- New query → paste → Run). Idempotent — safe to re-run.
--
-- Scope: this is ONLY the user's personal collection data (CollectionItem).
-- The reference catalog (platforms/games/prices) stays the static JSON feed at
-- data.retrostacks.com — Supabase never needs a copy of it. A collection row
-- references a catalog entry by its slug (`catalog_slug`), not a foreign key,
-- because the catalog isn't in this database.
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
