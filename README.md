# RetroStacks — monorepo

Track retro **video game systems, games, and accessories** — a personal
collection manager backed by a comprehensive reference catalog. US market first,
EU/JP later.

> **Naming:** everything is now **RetroStacks** (app, Xcode target, bundle id
> `com.levidahlstrom.RetroStacks`, this repo). Domain `retrostacks.com` to be
> registered (GoDaddy).

## Layout

| Path | What |
| --- | --- |
| [`apple/`](apple/) | Native SwiftUI app for **macOS / iPadOS / iOS** (SwiftData). Currently UI + mock data only. See [`apple/README.md`](apple/README.md). |
| [`api/`](api/) | Backend (catalog DB + REST API + pricing adapters). Not started — waiting on domain registration. See [`api/README.md`](api/README.md). |

## Status

- **App**: full UI wired, mock catalog (10 US platforms, ~30 consoles,
  ~40 games, ~25 accessories), Dashboard / Collection / Wishlist / Catalog /
  Platforms, real console photos, a pricing adapter layer with an offline default.
  macOS build succeeds; type-checks clean under Swift 6 for macOS 26 & iOS 26.
- **API**: design pending. The app talks only to `SampleData` + the built-in
  pricing guide today; the canonical pricing schema (`Services/Pricing/`) is
  written to double as the backend contract, and the `CatalogRepository` /
  `RemotePricingProvider` seams wait on a registered domain.
