# RetroStacks — monorepo

Track retro **video game systems, games, and accessories** — a personal
collection manager backed by a comprehensive reference catalog. US market first,
EU/JP later.

> **Naming:** everything is **RetroStacks** (app, Xcode target, bundle id
> `com.levidahlstrom.RetroStacks`, this repo). The app's catalog and your
> collection both live in Supabase; a static JSON feed is still published at
> `data.retrostacks.com` (GitHub Pages, custom domain via GoDaddy DNS) for the
> price guide and as a build artifact.

**Current version: 0.5.0** — see [`FEATURES.md`](FEATURES.md#version-history) for
the version history (semver; tags are `v0.1.0`…).

## Layout

| Path | What |
| --- | --- |
| [`apple/`](apple/) | Native SwiftUI app for **macOS / iPadOS / iOS** (SwiftData). Real catalog data + optional Supabase collection sync. See [`apple/README.md`](apple/README.md). |
| [`api/`](api/) | Catalog data pipeline: IGDB/libretro ingesters → `api/data/generated/*.json`, the build that emits the static `/v1/*.json` feed (GitHub Pages), the script that loads the catalog into Supabase, and PriceCharting / RetroGameCollector tooling. See [`api/README.md`](api/README.md). |
| [`supabase/`](supabase/) | Postgres + auth: the shared catalog (`catalog_items`, admin curation), and optional multi-device collection sync (magic-link sign-in). Live — see [`supabase/README.md`](supabase/README.md). |

## Status

- **App**: full UI wired — Dashboard / Collection / Wishlist / Catalog, a
  system-first "browse by platform" flow, barcode scanning (iOS), photo
  attachments, JSON/CSV backup, and optional Supabase sign-in for
  multi-device collection sync (local-first either way — signed out is a
  fully functional mode). SwiftLint-clean (`Scripts/lint.sh`), an ongoing
  real accessibility audit (`RetroStacksUITests` — see `BACKLOG.md`), and a
  regression test suite (`RetroStacksTests`) covering the sync/session/seed
  paths that have actually broken in practice.
- **Catalog data**: 19 platforms (gen 2–6: NES, SNES, N64, Genesis, Game Boy,
  Atari 2600, PS1, PS2, Dreamcast, GameCube, ColecoVision, Intellivision,
  Master System, TurboGrafx-16, Neo Geo, Saturn, 3DO, CD-i, Jaguar) and
  ~22,000 generated items (before admin exclusions), from IGDB +
  libretro-database, each tagged with regions (the app shows North America by
  default; EU/JP is a per-screen toggle). `api/data/curated.json` stays the
  hand-authored, always-wins source for the ~66 flagship entries (prices, rich
  summaries, consoles/accessories, verified art). The app reads the catalog
  from Supabase (`SupabaseCatalogRepository`); an admin can exclude junk
  entries catalog-wide.
- **Collection sync**: Supabase Auth (magic link, paste-the-link-back — no
  URL-scheme deep link, so no Xcode target changes needed) + Postgres,
  wired end-to-end and unit-tested (Keychain round-trip, wire format,
  last-write-wins merge), and exercised with a real live sign-in
  (2026-09-15/16). Photo sync is the piece still pending — see `BACKLOG.md`.
