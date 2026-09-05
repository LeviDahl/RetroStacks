# Video Game Tracker — monorepo

Track retro **video game systems, games, and accessories** — a personal
collection manager backed by a comprehensive reference catalog. US market first,
EU/JP later.

## Layout

| Path | What |
| --- | --- |
| [`apple/`](apple/) | Native SwiftUI app for **macOS / iPadOS / iOS** (SwiftData). Currently UI + mock data only. See [`apple/README.md`](apple/README.md). |
| [`api/`](api/) | Backend (catalog DB + REST API). Not started — waiting on domain registration. See [`api/README.md`](api/README.md). |

## Status

- **App**: full UI skeleton wired, mock catalog (10 US platforms, ~30 consoles,
  ~40 games, ~25 accessories), Dashboard / Collection / Wishlist / Catalog /
  Platforms. Type-checks clean under Swift 6 against the macOS 26 & iOS 26 SDKs.
  No `.xcodeproj` committed yet — see `apple/README.md` for the one-time setup.
- **API**: design pending. The app talks only to `Services/SampleData.swift`
  today; the seam for a real `CatalogRepository` is called out in the app README.
