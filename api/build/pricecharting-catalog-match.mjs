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
//      2026-09-18 before building this (see FEATURES.md): the actual NES
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
// Read-only against Supabase by default — the app's own public anon key,
// no service role key needed for a plain (dry-run) pass. Writes a JSON
// report either way; pass --execute to actually soft-delete the flagged
// items (needs SUPABASE_SERVICE_ROLE_KEY too, only then — see excludeSlugs).
// User's own explicit instruction 2026-09-18: do the exclusion directly
// rather than only report-and-wait-for-a-human, on the strength of it being
// the same reversible deleted_at tombstone the in-app exclude button and
// every sync path already use (admin_restore_catalog_items undoes it by
// slug). Real writes to a shared table regardless — --execute is opt-in,
// never the default, and always run a plain (dry-run) pass first to read
// the report before trusting it enough to add --execute.
//
// A match tagged "[Homebrew]" in PriceCharting's own product-name is
// suggested for exclusion too, not "keep" — user's call 2026-09-18: modern
// homebrew doesn't belong in the catalog even when it's a real, physically-
// sold item with genuine PriceCharting market value. See HOMEBREW_PATTERN.
//
//   PRICECHARTING_TOKEN=…  node api/build/pricecharting-catalog-match.mjs --platform nes
//   node api/build/pricecharting-catalog-match.mjs --platform nes --limit 20   # testing
//   PRICECHARTING_TOKEN=… SUPABASE_SERVICE_ROLE_KEY=…  \
//     node api/build/pricecharting-catalog-match.mjs --platform nes --execute
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
// (see FEATURES.md). Only platforms actually checked are listed; add more
// only after confirming the same way, not by guessing the naming pattern.
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
const execute = args.includes("--execute");

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
    const year = item.release_year_na;
    // A release year past the platform's discontinuation is sufficient on
    // its own — no legitimate NA release happens decades later, regardless
    // of publisher. A publisher-frequency veto here previously hid every
    // item from a prolific homebrew author (e.g. an N64 ROM-hacker with 18
    // titles under one handle) even when the year was unambiguous.
    if (year != null && discontinuedYearNA != null && year > discontinuedYearNA) return true;
    if (year != null) return false;

    const pub = item.manufacturer_or_publisher?.trim();
    const publisherIsRare = pub ? (publisherCounts.get(pub) ?? 0) <= RARE_PUBLISHER_THRESHOLD : true;
    return publisherIsRare;
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
  const exact = inPlatform.find((p) => normalize(p["product-name"]) === target);
  if (exact) return { match: exact, quality: "exact" };
  // Found live checking Atari 2600 before trusting this against the real
  // catalog: plain substring containment produces real false positives on
  // short/generic words — "Bloody Human Freeway" (a joke title) matched
  // "Freeway [Zellers]", "Punch Chess" matched "Chess [Green Label]",
  // "Kelly Kangaroo" matched plain "Kangaroo". A loose match here isn't
  // trustworthy enough to *confirm* anything, so it no longer does —
  // callers get this back as "quality: partial" and treat it as neither a
  // confident keep nor a confident exclude, just a flag for a human to
  // look at directly.
  const partial = inPlatform.find((p) => {
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

// User's own call 2026-09-18: modern homebrew doesn't belong in the
// catalog even when it's a real, physically-sold product with genuine
// PriceCharting market value (e.g. "Battle Kid 2: Mountain of Torment
// [Homebrew]") — "presence in PriceCharting" alone isn't the same as
// "keep," it just means "not a phantom ROM-hack that was never sold."
// PriceCharting tags these explicitly in product-name; trust that tag
// rather than guessing from our own fields. Matches "home" inside *any*
// bracket tag, not the literal word "homebrew" — found live checking
// Atari 2600 that PriceCharting's own data has at least one typo'd tag
// ("[Homewbrew]"), so an exact-word match silently misses real cases.
const HOMEBREW_PATTERN = /\[[^\]]*home/i;

// Found live checking Genesis before trusting Atari 2600's pattern here
// too: the [Homebrew] tag alone is nowhere near complete — most of a
// sample "keep" list turned out to have PriceCharting's own release-date
// in 2011-2025, genuinely modern indie/homebrew PriceCharting just never
// tagged. If PriceCharting's *own* date for the matched item is itself
// past the platform's commercial window, treat that exactly like an
// explicit homebrew tag — same signal our own review-candidate heuristic
// already uses, just applied to PriceCharting's date instead of ours.
function classify(found, discontinuedYearNA) {
  if (!found) return "exclude-not-found";
  if (found.quality === "partial") return "uncertain";
  if (HOMEBREW_PATTERN.test(found.match["product-name"])) return "exclude-homebrew";
  const pcYear = found.match["release-date"] ? Number(found.match["release-date"].slice(0, 4)) : null;
  if (pcYear != null && discontinuedYearNA != null && pcYear > discontinuedYearNA) return "exclude-homebrew";
  return "keep";
}

// MARK: - Exclusion (--execute only)

async function excludeSlugs(slugs) {
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    console.error("SUPABASE_SERVICE_ROLE_KEY is required for --execute.");
    process.exit(1);
  }
  // Direct PATCH with the service role key, not the admin_exclude_catalog
  // _items RPC — that RPC's admin check is auth.uid()-based (a signed-in
  // user's JWT claim), which service_role calls don't carry, so it would
  // always raise "not authorized" here. Same end state either way: sets
  // deleted_at, the identical soft-delete tombstone every sync path (and
  // the in-app exclude button) already respects — fully reversible by
  // clearing it, nothing hard-deleted.
  const url = new URL(`${SUPABASE_URL}/rest/v1/catalog_items`);
  url.searchParams.set("slug", `in.(${slugs.map((s) => `"${s}"`).join(",")})`);
  url.searchParams.set("owner_user_id", "is.null");
  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({ deleted_at: new Date().toISOString() }),
  });
  if (!res.ok) throw new Error(`Exclude PATCH failed: HTTP ${res.status} — ${await res.text()}`);
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
      suggestion: classify(found, platform.discontinuedYearNA),
    });
    if (checked % 25 === 0 || checked === candidates.length) {
      const excludeCount = results.filter((r) => r.suggestion.startsWith("exclude")).length;
      console.log(`  [${checked}/${candidates.length}] ${excludeCount} exclude candidates so far`);
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
  const homebrew = results.filter((r) => r.suggestion === "exclude-homebrew").length;
  const notFound = results.filter((r) => r.suggestion === "exclude-not-found").length;
  const uncertain = results.filter((r) => r.suggestion === "uncertain").length;
  console.log(
    `\nDone. ${keep} keep, ${homebrew} exclude (homebrew), ${notFound} exclude (not found), ` +
      `${uncertain} uncertain (partial match — needs a human look, not auto-excluded).`
  );
  console.log(`Report written to ${outPath}`);

  if (execute) {
    // "uncertain" (a loose substring match, not a confident one) is
    // deliberately excluded from this list, not just from "keep" — a
    // false "keep" is easy to miss later, but so is silently excluding
    // something a partial match might actually have confirmed was real.
    const toExclude = results.filter((r) => r.suggestion.startsWith("exclude")).map((r) => r.slug);
    if (!toExclude.length) {
      console.log("Nothing to exclude.");
      return;
    }
    console.log(`\n--execute: excluding ${toExclude.length} items (soft delete, reversible)...`);
    await excludeSlugs(toExclude);
    console.log("Done.");
    if (uncertain > 0) console.log(`${uncertain} "uncertain" items were left alone — review those by hand.`);
  } else if (homebrew + notFound + uncertain > 0) {
    console.log("(dry run — pass --execute to actually exclude the flagged items; \"uncertain\" ones never are)");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
