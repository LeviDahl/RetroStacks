# api

Backend for Video Game Tracker: the reference catalog database (consoles, games,
accessories for major US systems) and the REST API the app will sync from.

**Not started.** Blocked on registering a domain for the API + DB.

## Intended shape

- The app's `Services/SampleData.swift` mock is authored to mirror what this API
  will return, so the client swap is mostly a decoding layer:
  `Platform` → `CatalogItem` (`console` / `game` / `accessory`) → pricing.
- Personal `CollectionItem` data stays on-device (SwiftData); the API is
  read-mostly reference data + valuation.
- US market first; `region` is already a field on the client model for EU/JP.

## TODO

- [ ] Pick stack + hosting
- [ ] Schema for platforms / catalog items / price history
- [ ] Seed from public retro databases
- [ ] `GET /catalog`, `GET /platforms`, valuation endpoints
- [ ] Client `CatalogRepository` implementation replacing the mock

## Image hosting (backlog)

The app now shows real **console** photos by hot-linking Wikimedia Commons
(`Special:FilePath` redirect endpoint) — see `attachConsolePhotos` in
`apple/.../Services/SampleData.swift`. Mostly Evan Amos public-domain studio
shots; one (Dreamcast) is CC BY-SA 3.0 and carries an attribution string.

Good enough to prototype, but for production we want our own image layer:

- [ ] **S3 + CloudFront (or R2)** bucket of normalized art we control — kills the
      hot-link dependency, lets us resize/optimize, and removes the "is this
      licensed for our use" question for game/accessory box art.
- [ ] Broaden beyond consoles: **games + accessories** art. Candidate upstreams:
      IGDB (Twitch API, needs OAuth app), TheGamesDB, LibRetro thumbnails
      (`thumbnails.libretro.com`, keyed by exact title) for game box art.
- [ ] Ingest pipeline: fetch upstream → dedupe/resize → upload → store the CDN
      URL + credit + license on each catalog item (fields already exist:
      `imageURLString`, `imageCredit`, `imageLicense`).
- [ ] Client: replace `AsyncImage` with a small cached async-image view (or keep
      `AsyncImage` + the bumped `URLCache` already set in `configureImageCache()`),
      and consider bundling a low-res fallback for offline first paint.
