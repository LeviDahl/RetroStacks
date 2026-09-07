#!/usr/bin/env node
// Turns the canonical api/data/catalog.json into the static files the app
// fetches. No framework, no deps — runs anywhere Node 18+ is.
//
//   node api/build/build.mjs            -> writes api/dist/v1/*
//
// Output (served at <base>/v1/…):
//   catalog.json      platforms + items (no prices)
//   price-guide.json  { guides: { <slug>: PriceGuide } }  — matches the Swift type
//   meta.json         version + counts + generatedAt
//
// The PriceGuide shape here is the wire contract. Keep it in sync with
// apple/RetroStacks/Services/Pricing/PricingModels.swift.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "data", "catalog.json");
const OUT = join(ROOT, "dist", "v1");

const feed = JSON.parse(readFileSync(SRC, "utf8"));
const generatedAt = new Date().toISOString();
const VERSION = "1";

// --- catalog.json : platforms + items, prices stripped -----------------------

const platforms = [...feed.platforms].sort(
  (a, b) => a.generation - b.generation || a.name.localeCompare(b.name),
);

const PRICE_KEYS = ["priceLoose", "priceComplete", "priceSealed", "priceGraded"];
const items = [...feed.items]
  .sort((a, b) => a.slug.localeCompare(b.slug))
  .map((it) => {
    const clean = { ...it };
    for (const k of PRICE_KEYS) delete clean[k];
    delete clean.salesVolumeYearly;
    return clean;
  });

// --- price-guide.json : derive a PriceGuide per item ------------------------

const CONDITION = {
  priceLoose: "loose",
  priceComplete: "cib",
  priceSealed: "new",
  priceGraded: "graded",
};

let priceChartingRefreshes = 0;
if (process.env.PRICECHARTING_TOKEN) {
  // Hook for a future live refresh: for each item, GET /api/product?t=…&upc|q,
  // map pennies -> points, set primaryProvider = "pricecharting".
  // Throttle to 1 req/sec (their hard cap). Not wired yet.
  priceChartingRefreshes = feed.items.length;
  console.warn(
    `PRICECHARTING_TOKEN present — live refresh not implemented yet, ` +
      `passing through seed prices for ${priceChartingRefreshes} items.`,
  );
}

const guides = {};
for (const it of feed.items) {
  const points = [];
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
  if (points.length === 0 && it.salesVolumeYearly == null) continue;

  guides[it.slug] = {
    catalogSlug: it.slug,
    points,
    salesVolumeYearly: it.salesVolumeYearly ?? null,
    asOf: generatedAt,
    primaryProvider: "sample_guide",
    contributingProviders: ["sample_guide"],
    externalProductIDs: {},
  };
}

// --- write -----------------------------------------------------------------

mkdirSync(OUT, { recursive: true });

const write = (name, obj) => {
  const path = join(OUT, name);
  writeFileSync(path, JSON.stringify(obj, null, 2) + "\n");
  console.log(`wrote ${path.replace(ROOT + "/", "")}`);
};

write("catalog.json", { version: VERSION, generatedAt, platforms, items });
write("price-guide.json", { version: VERSION, generatedAt, guides });
write("meta.json", {
  version: VERSION,
  generatedAt,
  platformCount: platforms.length,
  itemCount: items.length,
  guideCount: Object.keys(guides).length,
  priceChartingRefreshes,
});

// tiny landing page so the Pages root isn't a 404
mkdirSync(join(ROOT, "dist"), { recursive: true });
writeFileSync(
  join(ROOT, "dist", "index.html"),
  `<!doctype html><meta charset=utf8><title>RetroStacks data</title>` +
    `<style>body{font:15px system-ui;margin:3rem auto;max-width:40rem;padding:0 1rem}` +
    `code{background:#eee;padding:.1em .3em;border-radius:3px}</style>` +
    `<h1>RetroStacks data feed</h1><p>Generated ${generatedAt}</p><ul>` +
    `<li><a href="v1/catalog.json">v1/catalog.json</a></li>` +
    `<li><a href="v1/price-guide.json">v1/price-guide.json</a></li>` +
    `<li><a href="v1/meta.json">v1/meta.json</a></li></ul>\n`,
);
console.log("wrote dist/index.html");
