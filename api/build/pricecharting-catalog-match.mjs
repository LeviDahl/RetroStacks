#!/usr/bin/env node
// Cross-references the live catalog's "review candidates" (see
// SystemGamesList.isReviewCandidate on the client — this replicates that
// exact heuristic in JS, since there's no shared code between the Swift app
// and this Node build pipeline) against PriceCharting's live API. Two goals
// in one pass:
//
//   1. A stronger curation signal than the release-date/rare-publisher
//      heuristic alone: PriceCharting only tracks things with real collector
//      market value, so absence there is a much more direct "this was never
//      actually sold" signal than an inferred pattern. Confirmed live
//      2026-09-18 before building this (see BACKLOG.md): the actual NES
//      bootleg that prompted the review-candidates feature is genuinely
//      absent from PriceCharting's whole catalog, while real small-batch
//      homebrew (e.g. "8-Bit Xmas 2022 [Homebrew]") is present with real
//      sales data — presence separates "real physical product" from
//      "ROM-hack/fan-patch never sold" better than our own heuristic does.
//   2. A real region signal for the EU/JP region backlog item: PriceCharting
//      splits regional releases into separate console names (NES vs PAL NES
//      vs Famicom) rather than a per-item field — confirmed live via the
//      same NES title showing up under multiple regional console names with
//      region-appropriate release dates.
//
// Read-only against Supabase — the app's own public anon key, no service
// role key needed, this never writes anything back to catalog_items. Writes
// a JSON report for a human to review; the resulting slugs feed into the
// app's existing admin bulk-exclude flow, this script doesn't exclude
// anything itself. Same reasoning as the client's own review-candidates
// toggle: assists a human decision, doesn't replace one.
//
//   PRICECHARTING_TOKEN=…  node api/build/pricecharting-catalog-match.mjs --platform nes
//   node api/build/pricecharting-catalog-match.mjs --platform nes --limit 20   # testing
//
// PriceCharting is an unmetered-by-call paid subscription, but hammering it
// is still bad manners — same PRICECHARTING_DELAY_MS default (1100ms) as the
// existing pricing/pricecharting.mjs enricher, and the same env var, so one
// token setup covers both.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
// Platforms were deliberately never migrated to Supabase (see supabase
// /schema.sql's own note) — still the small, bundled, local-only set the
// app ships with. curated.json is the same source CatalogSeedStore's own
// build step (sync-seed.mjs) reads.
const CURATED_PATH = join(ROOT, "api", "data", "curated.json");
const SUPABASE_URL = "https://vethkqrlcacmlffuzlnx.supabase.co";
// Safe to ship (see SupabaseConfig.swift's own comment) — RLS, not secrecy
// of this key, is what scopes access. Read-only usage here regardless.
const SUPABASE_ANON_KEY = "sb_publishable_jJEKk7jnVq6rRjgwAP5yOQ_P3fi4WCz";
const PRICECHARTING_ENDPOINT = "https://www.pricecharting.com/api/products";

// A real publisher published many games on a platform; a ROM hacker's own
// handle published one or two — same threshold as SystemGamesListCatalog
// .swift's rarePublisherThreshold. Keep these two in sync by hand; there's
// no shared source between the Swift app and this script.
const RARE_PUBLISHER_THRESHOLD = 3;

// PriceCharting's regional console-name values for each of our platform
// slugs — confirmed live 2026-09-18 by searching real titles and checking
// which console-name values their regional releases actually show up under
// (see BACKLOG.md). Only platforms actually checked are listed; add more
// only after confirming the same way, not by guessing the naming pattern.
const CONSOLE_NAMES = {
  nes: { NA: ["NES"], EU: ["PAL NES"], JP: ["Famicom"] },
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
    `No confirmed PriceCharting console-name mapping for platform "${platformSlug}". ` +
      `Only ${Object.keys(CONSOLE_NAMES).join(", ")} are verified so far — see CONSOLE_NAMES's comment.`
  );
  process.exit(1);
}
const allConsoleNames = new Set(Object.values(consoleNames).flat());

function clampInt(raw, fallback, min, max) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}
const delayMs = clampInt(process.env.PRICECHARTING_DELAY_MS, 1100, 250, 10000);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// MARK: - Supabase reads

async function supabaseGet(path, params) {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const res = await fetch(url, {
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}` },
  });
  if (!res.ok) throw new Error(`Supabase GET ${path} failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

function loadPlatform(slug) {
  const curated = JSON.parse(readFileSync(CURATED_PATH, "utf8"));
  const platform = curated.platforms.find((p) => p.slug === slug);
  if (!platform) throw new Error(`No platform "${slug}" in ${CURATED_PATH} — is that the right slug?`);
  return platform;
}

async function fetchAllCatalogItems(slug) {
  const pageSize = 1000;
  let offset = 0;
  const all = [];
  for (;;) {
    const page = await supabaseGet("catalog_items", {
      platform_slug: `eq.${slug}`,
      owner_user_id: "is.null",
      deleted_at: "is.null",
      select: "slug,name,kind,release_year_na,manufacturer_or_publisher",
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

// MARK: - Review-candidate heuristic (mirrors SystemGamesListCatalog.swift)

function findReviewCandidates(items, discontinuedYearNA) {
  const publisherCounts = new Map();
  for (const item of items) {
    const pub = item.manufacturer_or_publisher?.trim();
    if (pub) publisherCounts.set(pub, (publisherCounts.get(pub) ?? 0) + 1);
  }

  return items.filter((item) => {
    const pub = item.manufacturer_or_publisher?.trim();
    const publisherIsRare = pub ? (publisherCounts.get(pub) ?? 0) <= RARE_PUBLISHER_THRESHOLD : true;
    if (!publisherIsRare) return false;

    const year = item.release_year_na;
    if (year == null) return true;
    return discontinuedYearNA != null && year > discontinuedYearNA;
  });
}

// MARK: - PriceCharting

function normalize(name) {
  return name
    .toLowerCase()
    .replace(/\[[^\]]*\]/g, " ") // strip bracket tags like [Homebrew], [5 Screw]
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/^the /, "");
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

function bestMatch(itemName, products) {
  const target = normalize(itemName);
  const inPlatform = products.filter((p) => allConsoleNames.has(p["console-name"]));
  let exact = inPlatform.find((p) => normalize(p["product-name"]) === target);
  if (exact) return { match: exact, quality: "exact" };
  let partial = inPlatform.find((p) => {
    const n = normalize(p["product-name"]);
    return n.includes(target) || target.includes(n);
  });
  if (partial) return { match: partial, quality: "partial" };
  return null;
}

function regionFor(consoleName) {
  for (const [region, names] of Object.entries(consoleNames)) {
    if (names.includes(consoleName)) return region;
  }
  return null;
}

// MARK: - Main

async function main() {
  const platform = loadPlatform(platformSlug);
  console.log(`Fetching "${platformSlug}" live catalog from Supabase...`);
  const items = await fetchAllCatalogItems(platformSlug);
  console.log(`  ${items.length} live public items, discontinuedYearNA=${platform.discontinuedYearNA}`);

  const allCandidates = findReviewCandidates(items, platform.discontinuedYearNA);
  console.log(`  ${allCandidates.length} review candidates (rare/missing publisher AND missing/late release year)`);
  const candidates = limit ? allCandidates.slice(0, limit) : allCandidates;
  if (limit) console.log(`  --limit ${limit}: checking only the first ${candidates.length}`);

  const results = [];
  let checked = 0;
  for (const item of candidates) {
    checked++;
    let products = [];
    try {
      products = await searchPriceCharting(item.name);
    } catch (err) {
      console.error(`  [${checked}/${candidates.length}] ${item.name}: search failed — ${err.message}`);
    }
    const found = bestMatch(item.name, products);
    results.push({
      slug: item.slug,
      name: item.name,
      releaseYearNA: item.release_year_na,
      manufacturerOrPublisher: item.manufacturer_or_publisher,
      priceChartingMatch: found
        ? {
            quality: found.quality,
            productName: found.match["product-name"],
            consoleName: found.match["console-name"],
            region: regionFor(found.match["console-name"]),
            releaseDate: found.match["release-date"] ?? null,
            loosePriceCents: found.match["loose-price"] ?? null,
          }
        : null,
      suggestion: found ? "keep" : "exclude-candidate",
    });
    if (checked % 25 === 0 || checked === candidates.length) {
      const excludeCount = results.filter((r) => r.suggestion === "exclude-candidate").length;
      console.log(`  [${checked}/${candidates.length}] ${excludeCount} not found in PriceCharting so far`);
    }
    if (checked < candidates.length) await sleep(delayMs);
  }

  const outPath = join(ROOT, "api", "data", `pricecharting-match-${platformSlug}.json`);
  writeFileSync(
    outPath,
    JSON.stringify(
      {
        platform: platformSlug,
        generatedAt: new Date().toISOString(),
        totalLiveItems: items.length,
        totalReviewCandidates: allCandidates.length,
        checked: results.length,
        results,
      },
      null,
      2
    )
  );

  const keep = results.filter((r) => r.suggestion === "keep").length;
  const exclude = results.filter((r) => r.suggestion === "exclude-candidate").length;
  console.log(`\nDone. ${keep} confirmed in PriceCharting (suggest keep), ${exclude} not found (exclude candidates).`);
  console.log(`Report written to ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
