# api

Backend for **RetroStacks**: the reference catalog database (consoles, games,
accessories for major US systems), the pricing aggregation, and the REST API the
app syncs from.

**Not started.** Blocked on registering the domain (`retrostacks.com`, GoDaddy)
for the API + DB.

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

## Pricing (adapter layer — schema already lives in the app)

The **canonical pricing schema** is defined client-side in
`apple/RetroStacks/Services/Pricing/PricingModels.swift` and is written to
be provider-neutral and dependency-free so it can be lifted into a shared package
**or re-implemented here as the API contract**. Core types:

| Type | Role |
| --- | --- |
| `MarketCondition` | price tier: `loose` / `cib` / `new` (sealed) / `graded` / `box_only` / `manual_only` |
| `PriceKind` | `marketValue`, `retailBuy`, `retailSell`, `listingLow`, `soldMedian`, `gamestopPreowned` |
| `PricePoint` | one `{condition, kind, amount (Decimal USD), observedAt, sampleSize, sourceURL}` |
| `ProviderPriceReport` | raw output of one adapter for one item |
| `PriceGuide` | merged, consumer-facing result (one `PricePoint` per `condition|kind`, + `salesVolumeYearly`, `asOf`, `primaryProvider`, `contributingProviders`, `externalProductIDs`) |
| `PricingProvider` | adapter protocol: `priceReport(for: PriceQuery) async throws -> ProviderPriceReport` |

The shape is **adapted from the PriceCharting Prices API** so their data maps in
with almost no translation, but nothing is PriceCharting-specific.

### Adapters (lite; one per service)

Order = priority. First provider with a value for a given `condition|kind` wins;
lower-priority providers backfill. Any provider failing is skipped (redundancy).

| Adapter | Status | Notes |
| --- | --- | --- |
| `PriceChartingProvider` | mapping complete, **needs a token** | `/api/product` by `id` / `upc` / `q`; prices are integer **pennies**; dates `YYYY-MM-DD`; **1 req/sec**; paid plan. Token via `PRICECHARTING_TOKEN` env for dev. |
| `EbayBrowseProvider` | stub | Browse API `item_summary/search`; cheapest listing → `listingLow`, sold median → `soldMedian` (needs Marketplace Insights). OAuth. |
| `GGDealsProvider` | stub | digital storefront prices → `listingLow` on `new`; modern/PC titles only. |
| `SampleGuideProvider` | live default | echoes the app's own seed/cache so pricing renders offline. |

### Where the adapters should eventually run

Client-side adapters are fine for a solo start, but the plan is to move them
**here**: the API aggregates providers, applies the merge policy, caches history,
and serves the app a normalized `PriceGuide`. The app would then keep only
`PricingModels` + a thin `RemotePricingProvider` hitting our endpoint. Until
then, the client's `PricingService` does the aggregation.

- [ ] `GET /price-guide?slug=…` → `PriceGuide` JSON (same shape as the client type)
- [ ] Server-side adapter implementations + API keys in a secrets manager
- [ ] `price_point` history table (append-only) for trend charts
- [ ] Nightly PriceCharting CSV ingest (Legendary tier; 1 file, thousands of rows)
      instead of per-item calls
- [ ] Fuzzy match our catalog `slug` ⇄ each provider's product id; cache in
      `PriceGuide.externalProductIDs`

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
