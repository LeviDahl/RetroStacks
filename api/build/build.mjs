#!/usr/bin/env node
// Emits the static files the app fetches, from a pluggable data source. No deps.
//
//   node api/build/build.mjs                 -> api/dist/  (SOURCE=local-file default)
//   SOURCE=mysql    … node api/build/build.mjs
//   SOURCE=supabase … node api/build/build.mjs
//   FEED_CNAME=data.retrostacks.com node …   -> also writes dist/CNAME
//
// Output (served at <base>/v1/…) — this is THE contract; keep it in sync with
// apple/RetroStacks/Services/Catalog/CatalogFeed.swift and PricingModels.swift:
//   catalog.json      { version, generatedAt, platforms[], items[] }   (no prices)
//   price-guide.json  { version, generatedAt, guides: { <slug>: PriceGuide } }
//   meta.json         version + counts + generatedAt
//
// A source module exports `loadCatalog() -> { platforms, items }` (see
// sources/local-file.mjs for the field shapes). A pricing enricher exports
// `refreshPrices(items) -> Map<slug, patch>` (see pricing/pricecharting.mjs).

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "dist", "v1");
const VERSION = "1";
const generatedAt = new Date().toISOString();

// --- load from the selected source ---------------------------------------------

const sourceName = process.env.SOURCE || "local-file";
const source = await import(`./sources/${sourceName}.mjs`);
const { platforms: rawPlatforms, items: rawItems } = await source.loadCatalog();
console.log(`source: ${sourceName} — ${rawPlatforms.length} platforms, ${rawItems.length} items`);

// --- optional pricing enrichment ---------------------------------------------

let priceChartingRefreshes = 0;
if (process.env.PRICECHARTING_TOKEN) {
  const { refreshPrices } = await import("./pricing/pricecharting.mjs");
  const patches = await refreshPrices(rawItems);
  for (const it of rawItems) {
    const patch = patches.get(it.slug);
    if (patch) {
      Object.assign(it, patch);
      priceChartingRefreshes++;
    }
  }
  console.log(`pricing: refreshed ${priceChartingRefreshes} items from PriceCharting`);
}

// --- catalog.json : platforms + items, prices stripped ----------------------

const platforms = [...rawPlatforms].sort(
  (a, b) => a.generation - b.generation || a.name.localeCompare(b.name),
);

const PRICE_KEYS = ["priceLoose", "priceComplete", "priceSealed", "priceGraded", "salesVolumeYearly"];
const items = [...rawItems]
  .sort((a, b) => a.slug.localeCompare(b.slug))
  .map((it) => {
    const clean = { ...it };
    for (const k of PRICE_KEYS) delete clean[k];
    return clean;
  });

// --- price-guide.json : a PriceGuide per item -----------------------------

const CONDITION = {
  priceLoose: "loose",
  priceComplete: "cib",
  priceSealed: "new",
  priceGraded: "graded",
};

const guides = {};
for (const it of rawItems) {
  const points = it.points ?? [];
  if (points.length === 0) {
    for (const [key, condition] of Object.entries(CONDITION)) {
      const amount = it[key];
      if (amount == null) continue;
      points.push({
        condition,
        kind: "marketValue",
        amount, // JSON number -> Swift Decimal
        currencyCode: "USD",
        observedAt: generatedAt,
        sampleSize: it.salesVolumeYearly ?? null,
        sourceURL: null,
      });
    }
  }
  if (points.length === 0 && it.salesVolumeYearly == null) continue;

  guides[it.slug] = {
    catalogSlug: it.slug,
    points,
    salesVolumeYearly: it.salesVolumeYearly ?? null,
    asOf: generatedAt,
    primaryProvider: it.primaryProvider ?? "sample_guide",
    contributingProviders: it.contributingProviders ?? [it.primaryProvider ?? "sample_guide"],
    externalProductIDs: it.externalProductIDs ?? {},
  };
}

// --- write --------------------------------------------------------------

mkdirSync(OUT, { recursive: true });

const write = (path, obj) => {
  const full = join(ROOT, "dist", path);
  writeFileSync(full, typeof obj === "string" ? obj : JSON.stringify(obj, null, 2) + "\n");
  console.log(`wrote dist/${path}`);
};

write("v1/catalog.json", { version: VERSION, generatedAt, platforms, items });
write("v1/price-guide.json", { version: VERSION, generatedAt, guides });
write("v1/meta.json", {
  version: VERSION,
  generatedAt,
  source: sourceName,
  platformCount: platforms.length,
  itemCount: items.length,
  guideCount: Object.keys(guides).length,
  priceChartingRefreshes,
});

write(
  "index.html",
  `<!doctype html><meta charset=utf8><title>RetroStacks data</title>` +
    `<style>body{font:15px system-ui;margin:3rem auto;max-width:40rem;padding:0 1rem}</style>` +
    `<h1>RetroStacks data feed</h1><p>Generated ${generatedAt} · source: ${sourceName}</p><ul>` +
    `<li><a href="v1/catalog.json">v1/catalog.json</a></li>` +
    `<li><a href="v1/price-guide.json">v1/price-guide.json</a></li>` +
    `<li><a href="v1/meta.json">v1/meta.json</a></li></ul>\n`,
);

if (process.env.FEED_CNAME) {
  write("CNAME", process.env.FEED_CNAME.trim() + "\n");
}
