# api — RetroStacks data feed

Reference data for the app: the catalog (consoles / games / accessories for 19
systems, gen 2–6) and pricing.

**Where the app reads from today:** the catalog comes from **Supabase**
(`public.catalog_items`, via `SupabaseCatalogRepository`) — see
[`../supabase/README.md`](../supabase/README.md). This directory is the *pipeline
that feeds it*: ingest → `api/data/generated/*.json` → `build.mjs` →
`migrate-catalog-to-supabase.mjs`. The static `/v1/*.json` feed built here is
still published to GitHub Pages and the app still reads `price-guide.json` from
it (`RemoteCatalogRepository.fetchPriceGuides`), but `catalog.json` is no longer
what the app syncs its catalog from.

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
- **`api/build/sources/`** — the swap point. `local-file.mjs` merges
  `api/data/curated.json` + `api/data/generated/*.json` (the generated files are
  **minified, one line each**, and marked `-diff` in `.gitattributes` — the
  ingesters write them that way). `mysql.mjs` / `supabase.mjs` are
  **skeletons**: implement `loadCatalog()` to return the shape `local-file.mjs`
  documents and the rest of the pipeline is unchanged.
- **`api/build/ingest/libretro.mjs`** — pulls a US game catalog per platform from
  **libretro-database** (No-Intro / Redump lists + genre/year/publisher/developer
  metadata) → `api/data/generated/<platform>.json`. Cartridge systems only
  (the original six: NES, SNES, Genesis, N64, Game Boy, Atari 2600);
  libretro-database has no genre/year/publisher for disc systems, so those come
  from IGDB instead (below). Superseded for those six by the IGDB re-ingest.
  Filters to licensed US releases (drops proto/beta/homebrew/multicart/re-release
  compilations; keeps only titles with metadata). Box art URLs point at the
  Libretro thumbnails CDN.
- **`api/build/ingest/igdb.mjs`** — the same job from the **IGDB API** (Twitch),
  which *does* have metadata + region-aware release dates, used for every
  platform in its `PLATFORMS` map (platform ids are resolved live by name). Each
  item carries `regions` (`NA`/`EU`/`JP`, from `release_dates.release_region`).
  Writes the identical `generated/<platform>.json` shape. Needs `IGDB_CLIENT_ID` +
  `IGDB_CLIENT_SECRET` (free — an app at dev.twitch.tv); `--dry-run` prints the
  APICalypse queries without a token. **Not wired into CI** — IGDB's 4 req/sec cap
  makes a full pull minutes long, so run it by hand (or a weekly job), review the
  diff, commit the JSON. build.mjs only ever reads the committed files.
  Two live-data gotchas worth knowing if this ever needs re-running from
  scratch (both fixed 2026-09-14, but IGDB could change again): the API
  silently omits `category` on ordinary games instead of sending `0`, and
  `release_dates.region` is a dead, deprecated field — the live one is
  `release_region`. Both are handled in the query/filter now, with the
  reasoning in a code comment at each spot.
- **`api/build/migrate-catalog-to-supabase.mjs`** — loads `dist/v1/catalog.json`
  (run `build.mjs` first) into Supabase as public `catalog_items` rows through the
  service-role-only `upsert_public_catalog_items()` function. Needs
  `SUPABASE_SERVICE_ROLE_KEY` (keep it in the gitignored `api/.env`, never in
  chat/commits). Re-runnable; a re-sync no longer un-excludes items an admin
  excluded (`deleted_at` is preserved). `--dry-run`, `--limit N`.
- **One-off / curation tooling** (all `--dry-run` capable, all read secrets from
  the environment): `pricecharting-catalog-match.mjs` (flags items PriceCharting
  has never heard of as exclusion candidates; writes gitignored
  `api/data/pricecharting-match-*.json`), `pricecharting-region-check.mjs`
  (second, PriceCharting-based region signal — a report, doesn't write),
  `restore-pricecharting-exclusions.mjs` (re-applies exclusions from those
  reports), `rgc-collection-import.mjs` / `rgc-hardware-import.mjs` (one-time
  RetroGameCollector import; header comments describe its original 10-platform
  scope, since widened).
- **`api/data/curated.json`** — the hand-authored set: prices, rich summaries,
  consoles + accessories, verified art. **This is the source of truth** — edit it
  directly. `node api/build/sync-seed.mjs` copies it into the app bundle as
  `apple/RetroStacks/Resources/CatalogSeed.json` (the first-launch seed the app
  decodes via `CatalogSeedStore`). On merge into the feed, curated wins over any
  generated game with a matching title (keeps its slug + prices).
- **`api/build/pricing/pricecharting.mjs`** — implemented, **dormant by default**.
  `refreshPrices(items)` returns per-slug price patches (pennies → dollars). Runs
  only with `PRICECHARTING_TOKEN` **and** `PRICECHARTING_ENABLE=1`; then it queries
  un-priced games (newest first), `PRICECHARTING_MAX` per run (default 400),
  `PRICECHARTING_DELAY_MS` apart (default 1100). Per-item errors are skipped, never
  fatal.
- **`.github/workflows/publish-data.yml`** — builds + deploys to GitHub Pages,
  nightly + on push to `api/**`. Live at `https://levidahl.github.io/RetroStacks/`.

## Client

`apple/RetroStacks/Services/Catalog/` — `CatalogRepository` (protocol),
`SupabaseCatalogRepository` (the live catalog source; the price guide it
delegates to `RemoteCatalogRepository`, which fetches `price-guide.json` with
`URLCache`/ETag), `CatalogSyncService` (`@MainActor @Observable`, upserts
platforms + items into SwiftData by `slug`, additive, never throws out), and
`Services/Pricing/RemotePricingProvider` (actor, reads `price-guide.json`). `SampleData` is the
first-launch seed + offline fallback + previews. Kicked off from
`RetroStacksApp` `.task`; "Sync catalog now" is in the Dashboard's View Options.

`BackendConfig.feedBaseURL` still points at the static feed (used for the price
guide). The catalog's origin is `SupabaseConfig` + `SupabaseCatalogRepository`.

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
- [x] Grow the real catalog beyond the 6 cartridge systems — done 2026-09-14
      (PS1/PS2/Dreamcast/GameCube) and expanded 2026-09-18/19 to 19 platforms
      (~22,000 generated items). See `FEATURES.md`'s Data feed and Platform
      expansion sections for what those runs found and fixed.
- [x] Catalog in Supabase instead of only static JSON — done 2026-09-17.
- [ ] Nightly PriceCharting CSV ingest (Legendary tier) instead of per-item calls
- [ ] Implement a DB source (`sources/supabase.mjs`) so the static feed can be
      built *from* Supabase (today the flow is JSON → Supabase, one way)

## Collection data (no iCloud)

No Apple Developer account → no CloudKit / iCloud KVS / iCloud Documents.

**Local-first, always**: JSON export/import (`CollectionArchive` ⇄ `.json` via
`fileExporter`/`fileImporter`, Merge or Replace) works with no account,
signed in or not — backup + manual "sync" by putting the file in a folder
Dropbox/Drive already syncs.

**Optional multi-device sync**: Supabase (Postgres + email/magic-link auth,
no Apple account needed) — wired up, see [`../supabase/README.md`](../supabase/README.md).
Signing in is opt-in; nothing about local-first behavior changes if you don't.
That's also where accounts/subscriptions would live for monetization later
(which itself needs the $99/yr Apple Developer Program, not pursued yet).

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
