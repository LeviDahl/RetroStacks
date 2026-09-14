# RetroStacks — monorepo

Track retro **video game systems, games, and accessories** — a personal
collection manager backed by a comprehensive reference catalog. US market first,
EU/JP later.

> **Naming:** everything is **RetroStacks** (app, Xcode target, bundle id
> `com.levidahlstrom.RetroStacks`, this repo). Catalog feed live at
> `data.retrostacks.com` (GitHub Pages, custom domain via GoDaddy DNS).

## Layout

| Path | What |
| --- | --- |
| [`apple/`](apple/) | Native SwiftUI app for **macOS / iPadOS / iOS** (SwiftData). Real catalog data + optional Supabase collection sync. See [`apple/README.md`](apple/README.md). |
| [`api/`](api/) | Backend: static catalog feed (build pipeline + IGDB/libretro ingesters, published to GitHub Pages) + a pricing adapter layer. See [`api/README.md`](api/README.md). |
| [`supabase/`](supabase/) | Optional multi-device collection sync (Postgres + magic-link auth) — live, see [`supabase/README.md`](supabase/README.md). |

## Status

- **App**: full UI wired — Dashboard / Collection / Wishlist / Catalog, a
  system-first "browse by platform" flow, barcode scanning (iOS), photo
  attachments, JSON/CSV backup, and optional Supabase sign-in for
  multi-device collection sync (local-first either way — signed out is a
  fully functional mode). SwiftLint-clean (`Scripts/lint.sh`), an ongoing
  real accessibility audit (`RetroStacksUITests` — see `BACKLOG.md`), and a
  regression test suite (`RetroStacksTests`) covering the sync/session/seed
  paths that have actually broken in practice.
- **Catalog data**: ~13,000+ items across all 10 launch platforms (NES, SNES,
  N64, Genesis, Game Boy, Atari 2600, PS1, PS2, Dreamcast, GameCube), built
  from IGDB + libretro-database and served as static JSON from
  `data.retrostacks.com`. `api/data/curated.json` stays the hand-authored,
  always-wins source of truth for the ~66 flagship entries (prices, rich
  summaries, consoles/accessories, verified art).
- **Collection sync**: Supabase Auth (magic link, paste-the-link-back — no
  URL-scheme deep link, so no Xcode target changes needed) + Postgres,
  wired end-to-end and unit-tested (Keychain round-trip, wire format,
  last-write-wins merge). Not yet exercised with a real live sign-in — see
  `BACKLOG.md`'s Multi-user section for what's still pending there.
