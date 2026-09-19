#!/usr/bin/env node
// One-time import of a PureGaming.org / RetroGameCollector public collection
// export (see Scripts/../ or the CSV this reads) into RetroStacks — creates
// `collection_items` rows for this account directly via Supabase (service
// role key, bypasses RLS — the app has no admin-side "bulk import" RPC and
// this is a one-time personal migration, not a recurring pipeline), and
// `catalog_items` rows (owner_user_id = this account, i.e. a private custom
// item) for RGC games that don't already exist in the shared catalog.
//
// Scope: only the 10 platforms RetroStacks currently supports. RGC systems
// outside that (handhelds, Xbox/PS3+/Switch) and RGC systems on RetroStacks'
// backlog-but-not-built list (Intellivision, Master System, Jaguar, Saturn,
// TurboGrafx-16, ColecoVision, 3DO) are deliberately skipped — see
// BACKLOG.md's "Platform expansion" section. The full RGC export CSV is kept
// so those can be cross-referenced once real ingest happens for those
// platforms, instead of re-scraping.
//
// Matching is conservative like pricecharting-catalog-match.mjs: an item
// only gets auto-imported on an unambiguous match (exact normalized title,
// or a uniquely-resolving base title once a parenthetical variant tag like
// "(5 screw)" is stripped). Anything that could plausibly match more than
// one catalog entry is left as "ambiguous" for a human to resolve by hand,
// never guessed.
import { readFileSync } from "fs";
import { randomUUID } from "crypto";

const SUPABASE_URL = "https://vethkqrlcacmlffuzlnx.supabase.co";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const USER_ID = "3741a221-920d-45a9-9b22-b7303cecfc15";

if (!SERVICE_KEY) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required");
  process.exit(1);
}

const args = process.argv.slice(2);
const csvPath = args[0];
const execute = args.includes("--execute");
if (!csvPath) {
  console.error("usage: rgc-collection-import.mjs <path-to-rgc-export.csv> [--execute]");
  process.exit(1);
}

// Only the platforms RetroStacks currently supports — see header comment.
const SYSTEM_TO_PLATFORM = {
  NES: "nes",
  N64: "n64",
  SNES: "snes",
  Genesis: "genesis",
  "Atari 2600": "atari-2600",
  "Game Boy": "game-boy",
  Dreamcast: "dreamcast",
  GameCube: "gamecube",
  "Playstation 2": "ps2",
  "Playstation 1": "playstation",
};

// RFC4180-ish: the export script (Python csv.DictWriter, excel dialect)
// wraps any field containing a comma in double quotes and doubles internal
// quotes — e.g. `"Win, Lose, or Draw"`. A naive split(",") breaks on those.
function parseCSVLine(line) {
  const fields = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQuotes) {
      if (c === '"') {
        if (line[i + 1] === '"') {
          cur += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cur += c;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ",") {
      fields.push(cur);
      cur = "";
    } else {
      cur += c;
    }
  }
  fields.push(cur);
  return fields;
}

function parseCSV(text) {
  const lines = text.trim().split("\n");
  return lines.slice(1).map((line) => {
    const [system, status, name, cart, manual, box] = parseCSVLine(line);
    return { system, status, name, cart: cart === "True", manual: manual === "True", box: box === "True" };
  });
}

function normalize(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

// Splits a trailing "(...)" tag off a title, e.g. "10-Yard Fight (5 screw)"
// -> { base: "10-Yard Fight", tag: "5 screw" }. RGC uses these for real
// cartridge variants, not vendor/condition noise (unlike PriceCharting's
// bracket tags), so they're a variant signal, not something to discard.
function splitVariant(name) {
  const m = name.match(/^(.*?)\s*\(([^)]+)\)\s*$/);
  if (!m) return { base: name, tag: null };
  return { base: m[1].trim(), tag: m[2].trim() };
}

// RGC and the catalog disagree on sequel numbering for a lot of NES/SNES
// titles — RGC's "Bases Loaded 2" is the catalog's "Bases Loaded II: Second
// Season", "Castlevania 2" vs "Castlevania II" — found by spot-checking the
// first dry run's "new" bucket, which was full of exact real titles the
// catalog already has under the roman-numeral spelling. Only covers 1-20;
// nothing here goes past a handful of sequels.
const ROMAN = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x",
  "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"];

function numeralVariants(normalized) {
  const words = normalized.split(" ");
  const variants = new Set();
  words.forEach((w, i) => {
    const n = Number(w);
    if (Number.isInteger(n) && n >= 1 && n <= 20) {
      const alt = [...words];
      alt[i] = ROMAN[n - 1];
      variants.add(alt.join(" "));
    }
    const romanIdx = ROMAN.indexOf(w);
    if (romanIdx >= 0) {
      const alt = [...words];
      alt[i] = String(romanIdx + 1);
      variants.add(alt.join(" "));
    }
  });
  return [...variants];
}

// Minor words dropped when comparing title word-sets, so "Batman" can match
// against "Batman: The Video Game" but not get lost among genuinely
// different subtitles.
const STOPWORDS = new Set(["the", "a", "an", "of", "and"]);

function significantWords(normalized) {
  return new Set(normalized.split(" ").filter((w) => w && !STOPWORDS.has(w)));
}

// True if `smaller`'s significant words are all present in `larger`'s —
// e.g. RGC's bare "DuckTales" is a subset of the catalog's "Disney's
// DuckTales", RGC's bare "Adventure Island" is a subset of "Hudson's
// Adventure Island". Directionless: caller tries both ways since either
// RGC or the catalog can be the fuller title.
function isWordSubset(smaller, larger) {
  if (smaller.size === 0) return false;
  for (const w of smaller) if (!larger.has(w)) return false;
  return true;
}

async function supabaseFetchAll(path, query) {
  let all = [];
  let offset = 0;
  const pageSize = 1000;
  while (true) {
    const url = `${SUPABASE_URL}/rest/v1/${path}?${query}&limit=${pageSize}&offset=${offset}`;
    const res = await fetch(url, {
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    });
    if (!res.ok) throw new Error(`${path} fetch failed: HTTP ${res.status} ${await res.text()}`);
    const rows = await res.json();
    all = all.concat(rows);
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

async function supabaseInsert(path, rows) {
  if (rows.length === 0) return;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(rows),
  });
  if (!res.ok) throw new Error(`${path} insert failed: HTTP ${res.status} ${await res.text()}`);
}

function slugify(platformSlug, name) {
  const s = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${platformSlug}-custom-${s}`.slice(0, 120);
}

function completenessFor(box, manual) {
  if (box && manual) return "completeInBox";
  if (box) return "boxedNoManual";
  return "loose";
}

async function main() {
  const csv = readFileSync(csvPath, "utf8");
  const rgcRows = parseCSV(csv).filter((r) => SYSTEM_TO_PLATFORM[r.system]);
  console.log(`${rgcRows.length} rows on in-scope platforms (of the full export)`);

  const platforms = [...new Set(rgcRows.map((r) => SYSTEM_TO_PLATFORM[r.system]))];

  // Catalog index per platform: normalized full title (name + variant) -> item,
  // normalized base name -> [items] (to detect ambiguity), and the raw game
  // list (for the word-subset fallback tier).
  const catalogByPlatform = new Map();
  for (const platformSlug of platforms) {
    const items = await supabaseFetchAll(
      "catalog_items",
      `platform_slug=eq.${platformSlug}&deleted_at=is.null&select=slug,name,variant,kind`
    );
    const fullIndex = new Map();
    const baseIndex = new Map();
    const games = [];
    for (const item of items) {
      // Matches against every kind, not just games — RGC's per-system lists
      // mix in hardware (consoles, controllers, multi-carts), and excluding
      // those from the index meant "NES Advantage Controller" or "Super
      // Nintendo Console" registered as "new" even when already cataloged,
      // just under `kind: console`/`accessory`. `games` keeps the name for
      // historical reasons but now holds every kind.
      const full = normalize(item.variant ? `${item.name} (${item.variant})` : item.name);
      fullIndex.set(full, item);
      const base = normalize(item.name);
      if (!baseIndex.has(base)) baseIndex.set(base, []);
      baseIndex.get(base).push(item);
      games.push({ ...item, wordSet: significantWords(base) });
    }
    catalogByPlatform.set(platformSlug, { fullIndex, baseIndex, games });
    console.log(`  ${platformSlug}: ${items.length} catalog items indexed`);
  }

  const existingCollection = await supabaseFetchAll(
    "collection_items",
    `user_id=eq.${USER_ID}&deleted_at=is.null&select=catalog_slug,status`
  );
  const alreadyTracked = new Set(existingCollection.map((r) => `${r.catalog_slug}::${r.status}`));
  console.log(`${existingCollection.length} existing live collection_items for this account\n`);

  const results = {
    matched: [], matchedNumeral: [], matchedBase: [], matchedSubset: [],
    ambiguous: [], new: [], newHardwareUnmatched: [], skippedAlreadyTracked: [],
  };

  function resolve(name, { fullIndex, baseIndex, games }) {
    const fullNorm = normalize(name);
    if (fullIndex.has(fullNorm)) return { slug: fullIndex.get(fullNorm).slug, tier: "matched" };

    for (const variant of numeralVariants(fullNorm)) {
      if (fullIndex.has(variant)) return { slug: fullIndex.get(variant).slug, tier: "matchedNumeral" };
    }

    const { base } = splitVariant(name);
    const baseNorm = normalize(base);
    const baseCandidates = baseIndex.get(baseNorm);
    if (baseCandidates?.length === 1) return { slug: baseCandidates[0].slug, tier: "matchedBase" };
    if (baseCandidates?.length > 1) return { tier: "ambiguous" };

    for (const variant of numeralVariants(baseNorm)) {
      const c = baseIndex.get(variant);
      if (c?.length === 1) return { slug: c[0].slug, tier: "matchedNumeral" };
      if (c?.length > 1) return { tier: "ambiguous" };
    }

    // Word-subset fallback: RGC's significant words fully contained in a
    // catalog title's (handles "DuckTales" vs "Disney's DuckTales", "Batman"
    // vs "Batman: The Video Game" — the catalog just spells out a publisher
    // prefix/subtitle RGC's bare name omits). Deliberately one-directional:
    // the reverse (catalog words ⊆ RGC words) looked right for stripping
    // RGC's own "Round Seal"/variant noise, but a live spot-check caught it
    // wrongly folding real sequels into their base game too — "Back to the
    // Future 2 & 3" and "Gauntlet 2" both word-subset-matched onto "Back to
    // the Future" / "Gauntlet" (the catalog's shorter, *different*, base-
    // game titles) since a short title is trivially a word-subset of nearly
    // any longer one that shares its words. Only auto-matches when exactly
    // one catalog game satisfies it — two or more is ambiguous, not a guess.
    const rgcWords = significantWords(baseNorm);
    const subsetMatches = games.filter((g) => isWordSubset(rgcWords, g.wordSet));
    // A candidate whose *only* extra word(s) beyond RGC's title are a pure
    // sequel number ("Infiltrator" -> "Infiltrator II", "Super Pitfall" ->
    // "Super Pitfall II") is a real risk, not noise: found live that both
    // are known distinct games from their numbered follow-up, and the
    // catalog may simply be missing the original rather than RGC omitting
    // "II". Demoted to ambiguous rather than silently guessed — even a case
    // where RGC's own title already spells out a matching subtitle (only
    // "ii" ends up "extra" once the shared subtitle words are excluded)
    // still gets deferred, trading a few good auto-matches for zero wrong
    // ones.
    const isNumeralWord = (w) => (Number.isInteger(Number(w)) && Number(w) >= 1 && Number(w) <= 20) || ROMAN.includes(w);
    const trustworthy = subsetMatches.filter((g) => {
      const extra = [...g.wordSet].filter((w) => !rgcWords.has(w));
      return !(extra.length > 0 && extra.every(isNumeralWord));
    });
    if (trustworthy.length === 1) return { slug: trustworthy[0].slug, tier: "matchedSubset" };
    if (subsetMatches.length > 1 || (subsetMatches.length === 1 && trustworthy.length === 0)) {
      return { tier: "ambiguous" };
    }

    return { tier: "new" };
  }

  // Names that read as hardware rather than a game — RGC doesn't distinguish
  // kind, so an unmatched item like this would otherwise get auto-created as
  // a fabricated `kind: game` custom catalog entry, which is simply wrong.
  // Routed to its own bucket instead of guessed; left for a manual add.
  const HARDWARE_PATTERN =
    /\b(console|controller|advantage|control(?: |-)?pad|control deck|pak|zapper|adapter|power pad|joystick|light ?gun|game genie|game ?shark|classic( mini)?|organizer|satellite|top loader)\b/i;

  for (const row of rgcRows) {
    const platformSlug = SYSTEM_TO_PLATFORM[row.system];
    const catalog = catalogByPlatform.get(platformSlug);
    const status = row.status === "wanted" ? "wishlist" : "owned";

    const { slug: resolvedSlug, tier } = resolve(row.name, catalog);
    const entry = { ...row, platformSlug, status, resolvedSlug: resolvedSlug ?? null };

    if (resolvedSlug && alreadyTracked.has(`${resolvedSlug}::${status}`)) {
      results.skippedAlreadyTracked.push(entry);
      continue;
    }
    if (tier === "new" && HARDWARE_PATTERN.test(row.name)) {
      results.newHardwareUnmatched.push(entry);
      continue;
    }
    results[tier].push(entry);
  }

  for (const [tier, rows] of Object.entries(results)) {
    console.log(`${tier}: ${rows.length}`);
  }

  const reportPath = "api/data/rgc-import-report.json";
  const fs = await import("fs");
  fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
  console.log(`\nReport written to ${reportPath}`);

  if (!execute) {
    console.log("\n(dry run — pass --execute to actually write collection_items / catalog_items)");
    return;
  }

  // New custom catalog items first, so their slugs exist before the
  // collection_items rows that reference them.
  const newCatalogRows = results.new.map((r) => {
    const { base, tag } = splitVariant(r.name);
    return {
      slug: slugify(r.platformSlug, r.name),
      platform_slug: r.platformSlug,
      kind: "game",
      name: tag ? base : r.name,
      variant: tag,
      owner_user_id: USER_ID,
      summary: "",
      submitted_for_public: false,
      updated_at: new Date().toISOString(),
    };
  });
  // Dedup slugs within this batch (two RGC rows could normalize to the same
  // custom slug) — keep the first, map the rest onto it.
  const seenSlugs = new Map();
  for (const row of newCatalogRows) {
    if (!seenSlugs.has(row.slug)) seenSlugs.set(row.slug, row);
  }
  const uniqueNewCatalogRows = [...seenSlugs.values()];
  console.log(`\nInserting ${uniqueNewCatalogRows.length} new custom catalog_items...`);
  for (let i = 0; i < uniqueNewCatalogRows.length; i += 200) {
    await supabaseInsert("catalog_items", uniqueNewCatalogRows.slice(i, i + 200));
  }

  for (const r of results.new) {
    r.resolvedSlug = slugify(r.platformSlug, r.name);
  }

  const toInsert = [
    ...results.matched, ...results.matchedNumeral, ...results.matchedBase,
    ...results.matchedSubset, ...results.new,
  ];
  const now = new Date().toISOString();
  const collectionRows = toInsert.map((r) => ({
    id: randomUUID(),
    user_id: USER_ID,
    catalog_slug: r.resolvedSlug,
    status: r.status,
    condition: r.status === "owned" ? "good" : null,
    completeness: r.status === "owned" ? completenessFor(r.box, r.manual) : null,
    has_box: r.box,
    has_manual: r.manual,
    has_inserts: false,
    has_original_packaging: r.box,
    grading_company: "none",
    notes: "",
    date_added: now,
    updated_at: now,
  }));

  console.log(`Inserting ${collectionRows.length} collection_items...`);
  for (let i = 0; i < collectionRows.length; i += 200) {
    await supabaseInsert("collection_items", collectionRows.slice(i, i + 200));
  }

  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
