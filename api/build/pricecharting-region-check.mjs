#!/usr/bin/env node
// Cross-checks catalog items against PriceCharting's regional console-name
// listings (NES / PAL NES / Famicom, etc. — the same signal
// pricecharting-catalog-match.mjs already uses) to build a second, real
// data source for the region filter, backing up igdb.mjs's own
// release_dates.release_region tagging.
//
// Why a second source at all: IGDB's region data is community-sourced and
// this codebase has already found real gaps in this exact field once (its
// old `region` property silently stopped populating — see igdb.mjs's
// comment history). User's call 2026-09-18: since the NES/SNES/etc. game
// libraries are finite and never growing, a full PriceCharting pass per
// platform is worth doing once and treating as durable, rather than just
// spot-checking a sample.
//
// This is a REPORT tool, not a writer — it doesn't touch `catalog_items
// .regions` itself. Reconciling PriceCharting's findings against IGDB's
// (once a re-ingest actually populates `regions` — this script is only
// useful after that) is a deliberate separate, reviewed step, not
// something to auto-merge blindly.
//
//   PRICECHARTING_TOKEN=…  node api/build/pricecharting-region-check.mjs --platform nes
//   node api/build/pricecharting-region-check.mjs --platform nes --limit 20
import { readFileSync, writeFileSync } from "fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SUPABASE_URL = "https://vethkqrlcacmlffuzlnx.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_jJEKk7jnVq6rRjgwAP5yOQ_P3fi4WCz";
const PRICECHARTING_ENDPOINT = "https://www.pricecharting.com/api/products";

// Same mapping as pricecharting-catalog-match.mjs (duplicated rather than
// imported — these are two independent one-off CLI tools, not a shared
// library, and the two copies are small enough that drift would be obvious
// on the next edit to either). Only platforms confirmed live are listed;
// see that script's own header for how each was verified.
const CONSOLE_NAMES = {
  nes: { NA: ["NES"], EU: ["PAL NES"], JP: ["Famicom"] },
  "atari-2600": { NA: ["Atari 2600"], EU: ["PAL Atari 2600"], JP: [] },
  snes: { NA: ["Super Nintendo"], EU: ["PAL Super Nintendo"], JP: ["Super Famicom"] },
  genesis: { NA: ["Sega Genesis"], EU: ["PAL Sega Mega Drive"], JP: ["JP Sega Mega Drive"] },
  "game-boy": { NA: ["GameBoy"], EU: ["PAL GameBoy"], JP: [] },
  n64: { NA: ["Nintendo 64"], EU: ["PAL Nintendo 64"], JP: ["JP Nintendo 64"] },
  playstation: { NA: ["Playstation"], EU: ["PAL Playstation"], JP: ["JP Playstation"] },
  dreamcast: { NA: ["Sega Dreamcast"], EU: ["PAL Sega Dreamcast"], JP: ["JP Sega Dreamcast"] },
  gamecube: { NA: ["Gamecube"], EU: ["PAL Gamecube"], JP: ["JP Gamecube"] },
  ps2: { NA: ["Playstation 2"], EU: ["PAL Playstation 2"], JP: ["JP Playstation 2"] },
};

const args = process.argv.slice(2);
const platformIdx = args.indexOf("--platform");
const platformSlug = platformIdx >= 0 ? args[platformIdx + 1] : "nes";
const limitIdx = args.indexOf("--limit");
const limit = limitIdx >= 0 ? Number(args[limitIdx + 1]) : undefined;

const pcToken = process.env.PRICECHARTING_TOKEN;
if (!pcToken) {
  console.error("PRICECHARTING_TOKEN is required.");
  process.exit(1);
}

const consoleNames = CONSOLE_NAMES[platformSlug];
if (!consoleNames) {
  console.error(
    `No confirmed PriceCharting console-name mapping for "${platformSlug}". Only ${Object.keys(CONSOLE_NAMES).join(", ")} are verified.`
  );
  process.exit(1);
}

function clampInt(raw, fallback, min, max) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}
const delayMs = clampInt(process.env.PRICECHARTING_DELAY_MS, 1100, 250, 10000);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function normalize(name) {
  return name
    .toLowerCase()
    .replace(/\[[^\]]*\]/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/^the /, "");
}

async function supabaseGet(path, params) {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const res = await fetch(url, { headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}` } });
  if (!res.ok) throw new Error(`Supabase GET ${path} failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

async function fetchAllGames(slug) {
  const pageSize = 1000;
  let offset = 0;
  const all = [];
  for (;;) {
    const page = await supabaseGet("catalog_items", {
      platform_slug: `eq.${slug}`,
      owner_user_id: "is.null",
      deleted_at: "is.null",
      kind: "eq.game",
      select: "slug,name,variant",
      order: "slug",
      limit: String(pageSize),
      offset: String(offset),
    });
    all.push(...page);
    if (page.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

async function searchPriceCharting(query) {
  const url = new URL(PRICECHARTING_ENDPOINT);
  url.searchParams.set("t", pcToken);
  url.searchParams.set("q", query);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`PriceCharting search failed: HTTP ${res.status}`);
  const body = await res.json();
  return body.products ?? [];
}

async function main() {
  const items = await fetchAllGames(platformSlug);
  const targets = limit ? items.slice(0, limit) : items;
  console.log(`${platformSlug}: ${items.length} live catalog games, checking ${targets.length}`);

  const results = [];
  for (let i = 0; i < targets.length; i++) {
    const item = targets[i];
    const query = item.variant ? `${item.name} ${item.variant}` : item.name;
    let products;
    try {
      products = await searchPriceCharting(query);
    } catch (err) {
      console.warn(`  [${i + 1}/${targets.length}] ${item.name}: search failed — ${err.message}`);
      results.push({ slug: item.slug, name: item.name, confirmedRegions: null, error: String(err.message) });
      await sleep(delayMs);
      continue;
    }

    const target = normalize(item.name);
    const confirmedRegions = new Set();
    let anyMatch = false;
    for (const [region, names] of Object.entries(consoleNames)) {
      const inRegion = products.filter((p) => names.includes(p["console-name"]));
      const match = inRegion.find((p) => normalize(p["product-name"]) === target);
      if (match) {
        confirmedRegions.add(region);
        anyMatch = true;
      }
    }

    results.push({
      slug: item.slug,
      name: item.name,
      confirmedRegions: anyMatch ? [...confirmedRegions] : [],
    });

    if ((i + 1) % 25 === 0) console.log(`  [${i + 1}/${targets.length}]`);
    await sleep(delayMs);
  }

  const summary = { NA: 0, EU: 0, JP: 0, none: 0, errors: 0 };
  for (const r of results) {
    if (r.error) { summary.errors++; continue; }
    if (r.confirmedRegions.length === 0) summary.none++;
    for (const region of r.confirmedRegions) summary[region]++;
  }
  console.log(`\nDone. Exact-title-match confirmations: NA ${summary.NA}, EU ${summary.EU}, JP ${summary.JP}, ` +
    `no PriceCharting match at all: ${summary.none}, search errors: ${summary.errors}`);

  const outPath = join(ROOT, "api", "data", `pricecharting-region-check-${platformSlug}.json`);
  writeFileSync(outPath, JSON.stringify({ platform: platformSlug, generatedAt: new Date().toISOString(), results }, null, 2));
  console.log(`Report written to ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
