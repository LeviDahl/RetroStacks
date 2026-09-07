# api — RetroStacks data feed

Reference data for the app: the catalog (consoles / games / accessories for major
US systems) and pricing. **No server, no database** — a nightly job turns a
canonical JSON file into static files served from a CDN. That's plenty for a solo
user and scales to millions of reads for ~$0; it graduates to a real API later
with **no client changes** (same URLs, same JSON shapes).

Personal `CollectionItem` data never touches this — it stays on device (SwiftData)
and syncs via iCloud/CloudKit.

## How it works

```
api/data/catalog.json        canonical source of truth (platforms + items + seed prices)
        │
        ▼  node api/build/build.mjs
api/dist/                     (gitignored — built by CI)
├── index.html
└── v1/
    ├── catalog.json          { version, generatedAt, platforms[], items[] }   (no prices)
    ├── price-guide.json      { version, generatedAt, guides: { <slug>: PriceGuide } }
    └── meta.json             version + counts + generatedAt
```

- **`api/build/build.mjs`** — zero-dependency Node. Splits the catalog into
  `catalog.json` (metadata) and `price-guide.json` (a `PriceGuide` per item,
  derived from the seed price fields). If `PRICECHARTING_TOKEN` is set it *will*
  do a live refresh — not implemented yet, currently passes seed prices through.
- **`api/build/export-catalog.swift`** — regenerates `api/data/catalog.json` from
  the app's `SampleData` (current source of truth). Run when `SampleData` changes;
  see the header comment. *Follow-up: invert this so `catalog.json` is primary and
  `SampleData` decodes the bundled copy.*
- **`.github/workflows/publish-data.yml`** — builds `api/dist` and publishes it to
  **GitHub Pages** nightly + on push to `api/data`/`api/build`.
  One-time: repo **Settings → Pages → Source: "GitHub Actions"**.
  Served at `https://<owner>.github.io/RetroStacks/` → later `data.retrostacks.com`
  via a `CNAME` (GoDaddy DNS) + repo Pages custom-domain setting.

## Client

`apple/RetroStacks/Services/Catalog/` — `CatalogRepository` (`Remote` fetches the
feed with `URLCache`/ETag; `Bundled` reads a shipped copy), `CatalogSyncService`
upserts platforms + items into SwiftData by `slug`, and
`Services/Pricing/RemotePricingProvider` reads `price-guide.json`. `SampleData`
stays as the first-launch seed + offline fallback + previews.

`BackendConfig.baseURL` holds the feed URL — swap it for the custom domain once
DNS is set.

## TODO

- [ ] Enable GitHub Pages (Settings → Pages → GitHub Actions) and run the workflow once
- [ ] Point `data.retrostacks.com` at it (GoDaddy `CNAME` → `<owner>.github.io`) and set `BackendConfig.baseURL`
- [ ] Invert the source of truth: bundle `catalog.json`, have `SampleData` decode it
- [ ] Grow the real catalog beyond the ~50 sample items

## Collection data (no iCloud)

No Apple Developer account → no CloudKit / iCloud KVS / iCloud Documents.
Current: **local JSON export/import** (`CollectionArchive` ⇄ `.json` via
`fileExporter`/`fileImporter`, Merge or Replace). Backup + manual "sync" by
putting the file in a folder Dropbox/Drive already syncs.

Automatic multi-device sync, if wanted later, would be **Supabase** (Postgres +
email/magic-link auth, no Apple account) or a tiny **Cloudflare Worker + token** —
that's also where accounts/subscriptions would live for monetization (which
itself needs the $99/yr Apple Developer Program, blocked for now).

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
