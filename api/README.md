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
