# api — RetroStacks data feed

Reference data for the app: the catalog (consoles / games / accessories for major
US systems) and pricing.

**The `/v1/*.json` contract is the whole interface.** Right now those files are
static, built by CI and served free from GitHub Pages — plenty for a solo user,
scales to millions of reads for ~$0. When it needs to become dynamic (a MySQL DB
at GoDaddy, a Postgres DB at Supabase, whatever), only the *source* of the build
changes; the emitted JSON, the URLs, and the entire app stay the same.

Personal `CollectionItem` data never touches this — see *Collection data* below.

## How it works

```
data source  ──▶  build.mjs  ──▶  api/dist/            (gitignored; published by CI)
                     ▲             ├── index.html
             pricing enricher      ├── CNAME           (if FEED_CNAME set)
                                   └── v1/
                                       ├── catalog.json      { version, generatedAt, platforms[], items[] }
                                       ├── price-guide.json  { version, generatedAt, guides: { <slug>: PriceGuide } }
                                       └── meta.json         version + counts + source + generatedAt
```

- **`api/build/build.mjs`** — zero-dep orchestrator. Loads from
  `sources/${SOURCE}.mjs` (default `local-file`), optionally runs a pricing
  enricher, emits the `v1/*.json` files. `SOURCE`, `FEED_CNAME`,
  `PRICECHARTING_TOKEN` are env vars (wired to repo variables/secrets in the
  workflow).
- **`api/build/sources/`** — the swap point. `local-file.mjs` reads
  `api/data/catalog.json` (the current source of truth). `mysql.mjs` /
  `supabase.mjs` are **skeletons**: implement `loadCatalog()` to return the shape
  `local-file.mjs` documents and the rest of the pipeline is unchanged.
- **`api/build/pricing/pricecharting.mjs`** — skeleton enricher. `refreshPrices(items)`
  returns per-slug price patches (pennies → dollars, 1 req/sec cap).
- **`api/data/catalog.json`** — canonical catalog for the `local-file` source.
  Regenerate from the app's `SampleData` with **`api/build/export-catalog.swift`**
  when SampleData changes (see its header). *Follow-up: invert this so
  `catalog.json` is primary and `SampleData` decodes the bundled copy.*
- **`.github/workflows/publish-data.yml`** — builds + deploys to GitHub Pages,
  nightly + on push to `api/**`. Live at `https://levidahl.github.io/RetroStacks/`.

## Client

`apple/RetroStacks/Services/Catalog/` — `CatalogRepository` /
`RemoteCatalogRepository` (fetch + `URLCache`/ETag), `CatalogSyncService`
(`@MainActor @Observable`, upserts platforms + items into SwiftData by `slug`,
additive, never throws out), and `Services/Pricing/RemotePricingProvider`
(actor, reads `price-guide.json`, top of the provider chain). `SampleData` is the
first-launch seed + offline fallback + previews. Kicked off from
`RetroStacksApp` `.task`; "Sync catalog now" is in the Dashboard's View Options.

`BackendConfig.feedBaseURL` is the single knob. A dynamic backend just needs to
serve the same `/v1/*.json` at its own base URL — the repository/provider code
doesn't change.

## Custom domain: data.retrostacks.com

1. **GoDaddy DNS** → add `CNAME` record: host `data`, points to
   `levidahl.github.io` (no trailing path).
2. **Set the domain on Pages** — either repo *Settings → Pages → Custom domain* =
   `data.retrostacks.com`, **or** set repo variable `FEED_CNAME=data.retrostacks.com`
   and re-run the workflow (build.mjs writes `dist/CNAME`).
3. Wait for GitHub's DNS check + cert (minutes–hours), tick *Enforce HTTPS*.
4. Flip `BackendConfig.feedBaseURL` to `https://data.retrostacks.com`.

**Done** — `https://data.retrostacks.com/v1/*.json` is live (HTTPS). Tick *Enforce
HTTPS* in Settings → Pages once GitHub enables it.

## TODO
- [ ] Invert the source of truth: bundle `catalog.json`, have `SampleData` decode it
- [ ] Grow the real catalog beyond the sample set
- [ ] Implement a DB source (`sources/mysql.mjs` or `sources/supabase.mjs`) when the
      catalog outgrows a hand-maintained file

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
