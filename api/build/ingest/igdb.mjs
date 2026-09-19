#!/usr/bin/env node
// Pulls a US game catalog per platform from the IGDB API (Twitch) and writes
// api/data/generated/<platform>.json — the same shape ingest/libretro.mjs
// produces, so sources/local-file.mjs merges it with no changes.
//
// Why a second ingester: libretro-database has no genre / year / publisher for
// disc systems (PS1/PS2/DC/GCN), and IGDB's metadata + region-aware release
// dates are better across the board. Run this to (a) add the disc systems and
// (b) re-enrich the cartridge systems libretro already covers.
//
//   IGDB_CLIENT_ID=…  IGDB_CLIENT_SECRET=…  node api/build/ingest/igdb.mjs
//   node api/build/ingest/igdb.mjs ps2 gamecube        # just these
//   node api/build/ingest/igdb.mjs --dry-run nes       # print the query, no calls
//
// This is NOT part of the nightly build. build.mjs reads the committed
// generated/*.json; run this by hand (or a separate weekly job), review the
// diff, commit. IGDB's rate limit is 4 req/sec — a full pull is minutes, not
// seconds, which is exactly why it stays out of CI.
//
// Auth: Twitch OAuth2 client-credentials. Create an app at
// https://dev.twitch.tv/console/apps → Client ID + Client Secret. No user login;
// the token is fetched here and cached in memory for the run (~60-day TTL, but
// we always mint a fresh one).

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data", "generated");

const TOKEN_URL = "https://id.twitch.tv/oauth2/token";
const IGDB = "https://api.igdb.com/v4";

// our platform slug -> IGDB platform id (https://api-docs.igdb.com, /platforms).
// These 10 ids were already in production use before this comment was
// written and are left as-is (re-verifying them live on every run would
// just be extra API calls for no benefit — they're known-good).
const PLATFORMS = {
  "atari-2600":  { igdb: 59,  system: "Atari 2600" },
  "nes":         { igdb: 18,  system: "Nintendo Entertainment System" },
  "snes":        { igdb: 19,  system: "Super Nintendo Entertainment System" },
  "n64":         { igdb: 4,   system: "Nintendo 64" },
  "game-boy":    { igdb: 33,  system: "Game Boy" },
  "genesis":     { igdb: 29,  system: "Sega Mega Drive/Genesis" },
  "playstation": { igdb: 7,   system: "PlayStation" },
  "ps2":         { igdb: 8,   system: "PlayStation 2" },
  "dreamcast":   { igdb: 23,  system: "Dreamcast" },
  "gamecube":    { igdb: 21,  system: "Nintendo GameCube" },
};

// 2026-09-18 platform expansion (see FEATURES.md) — added without a session
// holding IGDB credentials to verify numeric platform ids against the live
// API, and hand-typed numeric ids found via web search disagreed with each
// other across sources (two different ids each for Sega Saturn and Atari
// Jaguar alone). Rather than risk a wrong-but-non-zero id silently pulling
// an entirely different platform's games (the existing 0-results guard
// below only catches an id matching *nothing*, not an id matching the
// *wrong* thing), these resolve their real numeric id live by exact IGDB
// platform name on first use instead of trusting a hardcoded number. Names
// confirmed against igdb.com/platforms's own listing (not guessed).
const PLATFORMS_BY_NAME = {
  "colecovision":       { igdbName: "ColecoVision", system: "ColecoVision" },
  "intellivision":      { igdbName: "Intellivision", system: "Intellivision" },
  "sega-master-system": { igdbName: "Sega Master System/Mark III", system: "Sega Master System" },
  "turbografx-16":      { igdbName: "TurboGrafx-16/PC Engine", system: "TurboGrafx-16" },
  "neo-geo":            { igdbName: "Neo Geo AES", system: "Neo Geo" },
  "saturn":             { igdbName: "Sega Saturn", system: "Sega Saturn" },
  "3do":                { igdbName: "3DO Interactive Multiplayer", system: "3DO Interactive Multiplayer" },
  "cd-i":               { igdbName: "Philips CD-i", system: "Philips CD-i" },
  "jaguar":             { igdbName: "Atari Jaguar", system: "Atari Jaguar" },
};

async function resolvePlatformId(igdbName) {
  const rows = await igdbPost("platforms", `fields id, name;\nwhere name = "${igdbName}";\nlimit 5;`);
  if (rows.length === 0) {
    throw new Error(`resolvePlatformId: no IGDB platform named "${igdbName}" — check the exact spelling against igdb.com/platforms`);
  }
  if (rows.length > 1) {
    throw new Error(`resolvePlatformId: "${igdbName}" matched ${rows.length} IGDB platforms (${rows.map((r) => r.id).join(", ")}) — need an exact, unambiguous name`);
  }
  return rows[0].id;
}

// IGDB release_date region codes (release_region, not the deprecated region
// field — see toItem's comment). 8 = Worldwide counts toward every region.
const NA_REGIONS = new Set([2, 8]);
const EU_REGIONS = new Set([1, 8]);
const JP_REGIONS = new Set([5, 8]);
// IGDB game.category — 0 = main game. Everything else (DLC, expansion, bundle,
// episode, mod, port, pack, update) is excluded from the catalog.
const MAIN_GAME = 0;
const PAGE = 500; // IGDB hard max per request

const ARTICLES = ["The", "A", "An", "Les", "La", "Le", "Los", "El", "Der", "Die", "Das"];

// ---------------------------------------------------------------------------

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const targets = args.filter((a) => !a.startsWith("--"));
const wanted = targets.length ? targets : [...Object.keys(PLATFORMS), ...Object.keys(PLATFORMS_BY_NAME)];

const gamesQuery = (platformId, afterId) =>
  [
    "fields name, slug, summary, first_release_date, category, version_parent,",
    "       genres.name, cover.image_id,",
    "       involved_companies.developer, involved_companies.publisher,",
    "       involved_companies.company.name,",
    "       release_dates.release_region, release_dates.y, release_dates.platform;",
    `where platforms = (${platformId})`,
    // Confirmed live 2026-09-14: IGDB omits `category` from the response
    // entirely (not `category: null` — the key is just absent) on ordinary
    // games. Only DLC/expansion/bundle/etc. get an explicit non-zero value.
    // Requiring `category = MAIN_GAME` alone matched ~0 games on every
    // platform tested; `= null` is what actually catches the unset case.
    `  & (category = ${MAIN_GAME} | category = null)`,
    "  & version_parent = null",
    `  & id > ${afterId};`,
    "sort id asc;",
    `limit ${PAGE};`,
  ].join("\n");

if (dryRun) {
  for (const slug of wanted) {
    if (PLATFORMS[slug]) {
      const cfg = PLATFORMS[slug];
      console.log(`\n--- ${slug} (IGDB platform ${cfg.igdb}) ---\n${gamesQuery(cfg.igdb, 0)}`);
    } else if (PLATFORMS_BY_NAME[slug]) {
      const cfg = PLATFORMS_BY_NAME[slug];
      console.log(`\n--- ${slug} (id resolved live by name — needs a token, can't preview here) ---`);
      console.log(`fields id, name;\nwhere name = "${cfg.igdbName}";\nlimit 5;`);
    } else {
      console.warn(`skip unknown platform: ${slug}`);
    }
  }
  process.exit(0);
}

const clientId = process.env.IGDB_CLIENT_ID;
const clientSecret = process.env.IGDB_CLIENT_SECRET;
if (!clientId || !clientSecret) {
  console.error(
    "IGDB_CLIENT_ID and IGDB_CLIENT_SECRET must be set " +
      "(create an app at https://dev.twitch.tv/console/apps). " +
      "Use --dry-run to inspect the queries without a token.",
  );
  process.exit(1);
}

const token = await getAppToken(clientId, clientSecret);
mkdirSync(OUT, { recursive: true });

for (const slug of wanted) {
  let cfg = PLATFORMS[slug];
  if (!cfg && PLATFORMS_BY_NAME[slug]) {
    const byName = PLATFORMS_BY_NAME[slug];
    const igdbId = await resolvePlatformId(byName.igdbName);
    console.log(`${slug}: resolved "${byName.igdbName}" -> IGDB platform ${igdbId}`);
    cfg = { igdb: igdbId, system: byName.system };
  }
  if (!cfg) { console.warn(`skip unknown platform: ${slug}`); continue; }

  const raw = await fetchAllGames(cfg.igdb);
  if (raw.length === 0) {
    // A real platform returning 0 IGDB rows is exactly what a bad/
    // unauthorized token or misconfigured Twitch app looks like: the request
    // still comes back 200 OK (no error to catch), just with an empty match.
    // Refusing to write is what stops that from silently overwriting a
    // previously-good generated/<slug>.json with an empty one.
    throw new Error(
      `${slug}: IGDB returned 0 games for platform ${cfg.igdb} — refusing to overwrite ` +
        `generated/${slug}.json with empty data. This almost always means the token/app ` +
        `isn't actually authorized against IGDB yet (Twitch app creation succeeding is not ` +
        `the same as IGDB access being live) rather than a real "no games" result. Verify with ` +
        `a raw curl call before re-running: curl -s -X POST https://api.igdb.com/v4/games ` +
        `-H "Client-ID: $IGDB_CLIENT_ID" -H "Authorization: Bearer <token>" ` +
        `-d "fields name; where platforms = (18); limit 5;"`,
    );
  }
  const items = raw
    .map((g) => toItem(slug, cfg, g))
    .filter(Boolean)
    .sort((a, b) => a.name.localeCompare(b.name));
  deduplicateSlugs(items);

  const path = join(OUT, `${slug}.json`);
  writeFileSync(
    path,
    // Minified on purpose: ~20MB pretty-printed across all platforms was
    // 200k+ lines per re-ingest in git. See .gitattributes.
    JSON.stringify({ platformSlug: slug, system: cfg.system, source: "igdb", generatedAt: new Date().toISOString(), items }) + "\n",
  );
  console.log(`${slug}: ${items.length} games (from ${raw.length} IGDB rows) -> data/generated/${slug}.json`);
}

// --- IGDB plumbing ---------------------------------------------------------

async function getAppToken(id, secret) {
  const params = new URLSearchParams({
    client_id: id,
    client_secret: secret,
    grant_type: "client_credentials",
  });
  const res = await fetch(`${TOKEN_URL}?${params}`, { method: "POST" });
  if (!res.ok) throw new Error(`Twitch token: HTTP ${res.status} ${await res.text()}`);
  const body = await res.json();
  if (!body.access_token) throw new Error("Twitch token: no access_token in response");
  return body.access_token;
}

async function igdbPost(path, query) {
  // 4 req/sec cap — space calls out.
  await sleep(280);
  const res = await fetch(`${IGDB}/${path}`, {
    method: "POST",
    headers: {
      "Client-ID": clientId,
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      "Content-Type": "text/plain",
    },
    body: query,
  });
  if (res.status === 429) {
    console.warn("  429 rate-limited — backing off 2s");
    await sleep(2000);
    return igdbPost(path, query);
  }
  if (!res.ok) throw new Error(`IGDB ${path}: HTTP ${res.status} ${await res.text()}`);
  return res.json();
}

async function fetchAllGames(platformId) {
  const all = [];
  let afterId = 0;
  for (;;) {
    const page = await igdbPost("games", gamesQuery(platformId, afterId));
    if (page.length === 0) break;
    all.push(...page);
    afterId = page[page.length - 1].id;
    if (page.length < PAGE) break;
  }
  return all;
}

// --- mapping -------------------------------------------------------------

// Found 2026-09-14: a small handful of IGDB entries per platform (distinct
// igdbIDs — genuine near-duplicate catalog entries, or titles that only
// differ by punctuation `slugify` strips, e.g. "Final Fantasy" vs.
// "Final Fantasy ++" both -> `final-fantasy`) collide on slug. The app's own
// seed loader (`CatalogSeedStore`) throws on a duplicate slug, so this has
// to be resolved here rather than left for sync-seed.mjs to trip over later.
// Appends `-<igdbID>` to *every* member of a colliding group (not just the
// second one) so the result is stable across re-runs regardless of
// insertion order.
function deduplicateSlugs(items) {
  const bySlug = new Map();
  for (const item of items) {
    if (!bySlug.has(item.slug)) bySlug.set(item.slug, []);
    bySlug.get(item.slug).push(item);
  }
  for (const group of bySlug.values()) {
    if (group.length < 2) continue;
    for (const item of group) item.slug = `${item.slug}-${item.igdbID}`;
  }
}

function toItem(platformSlug, cfg, g) {
  if (!g.name) return null;

  // Region tracking, not a drop filter — changed 2026-09-18 (see FEATURES.md's
  // "EU / JP region switch"). Used to discard anything without a confirmed NA
  // release; now keeps everything and records which regions actually had a
  // release, so the app can filter instead of the ingest silently deciding.
  //
  // Confirmed live 2026-09-14: `release_dates.region` is IGDB's old, DEPRECATED
  // field — never populated anymore, silently returning nothing instead of
  // erroring (queryable but dead). The real field is `release_region`, backed
  // by the /v4/release_date_regions lookup table; it reuses the same integer
  // ids the old `region` enum used (1 = europe, 2 = north_america, 5 = japan,
  // 8 = worldwide — see NA_REGIONS/EU_REGIONS/JP_REGIONS above) plus two new
  // ones (9 = korea, 10 = brazil) tacked on, neither tracked here (out of
  // this app's scope). `datesWithRegion` isolates entries that actually carry
  // a value — a game with genuinely no region data anywhere gets `regions:
  // null` (unconfirmed, not "confirmed non-NA"), which the app treats as
  // "assume NA" to match the old behavior for anything ingest can't speak to.
  //
  // IGDB's own region tagging is community-sourced and has had gaps before in
  // this exact field (see the deprecated-`region` history above) — treat a
  // non-NA-only `regions` result as a signal worth corroborating, e.g. against
  // PriceCharting's regional console-name listings (see
  // `pricecharting-region-check.mjs`), not as certain on its own.
  const dates = (g.release_dates ?? []).filter(
    (d) => d.platform === cfg.igdb || d.platform == null,
  );
  const datesWithRegion = dates.filter((d) => d.release_region != null);
  const naDates = dates.filter((d) => NA_REGIONS.has(d.release_region));
  const euDates = dates.filter((d) => EU_REGIONS.has(d.release_region));
  const jpDates = dates.filter((d) => JP_REGIONS.has(d.release_region));
  const regions =
    datesWithRegion.length === 0
      ? null
      : [naDates.length && "NA", euDates.length && "EU", jpDates.length && "JP"].filter(Boolean);

  const year =
    minYear(naDates) ??
    minYear(dates) ??
    (g.first_release_date ? new Date(g.first_release_date * 1000).getUTCFullYear() : null);

  const title = cleanTitle(g.name);
  if (!title) return null;

  const companies = g.involved_companies ?? [];
  const publisher = companies.find((c) => c.publisher)?.company?.name ?? null;
  const developer = companies.find((c) => c.developer)?.company?.name ?? null;

  return {
    slug: `${platformSlug}-${slugify(title)}`,
    platformSlug,
    kind: "game",
    name: title,
    releaseYearNA: year,
    regions,
    manufacturerOrPublisher: publisher,
    developer,
    genre: g.genres?.[0]?.name ?? null,
    summary: g.summary ?? null,
    imageURL: g.cover?.image_id
      ? `https://images.igdb.com/igdb/image/upload/t_cover_big/${g.cover.image_id}.jpg`
      : null,
    imageCredit: "Cover via IGDB",
    imageLicense: "Publisher artwork",
    igdbID: g.id,
    igdbSlug: g.slug ?? null,
    source: "igdb",
  };
}

// Function declaration (not `const`), so it's hoisted — toItem calls this
// from the top-level loop above, before this line runs.
function minYear(ds) {
  const ys = ds.map((d) => d.y).filter((y) => Number.isFinite(y));
  return ys.length ? Math.min(...ys) : null;
}

// Match ingest/libretro.mjs so slugs collide (curated/generated dedupe works).
function cleanTitle(raw) {
  let t = raw
    .replace(/\s*\([^)]*\)/g, "")
    .replace(/\s*\[[^\]]*\]/g, "")
    .replace(/\s*[-:]\s*(Disc|Disk)\s*\d+.*$/i, "")
    .trim();
  for (const art of ARTICLES) {
    const tail = new RegExp(`,\\s*${art}$`);
    if (tail.test(t)) t = `${art} ${t.replace(tail, "")}`;
  }
  return t.trim();
}

// Function declaration (not `const`), so it's hoisted — toItem calls this
// from the top-level loop above, before this line runs.
function slugify(s) {
  return s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "") // strip combining diacritics
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

// Function declaration (not `const`), so it's hoisted — igdbPost/fetchAllGames
// call this before this line runs in the script's top-level execution order.
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
