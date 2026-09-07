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

// our platform slug -> IGDB platform id (https://api-docs.igdb.com, /platforms)
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

// IGDB release_date region codes. 2 = North America; 8 = Worldwide.
const NA_REGIONS = new Set([2, 8]);
// IGDB game.category — 0 = main game. Everything else (DLC, expansion, bundle,
// episode, mod, port, pack, update) is excluded from the catalog.
const MAIN_GAME = 0;
const PAGE = 500; // IGDB hard max per request

const ARTICLES = ["The", "A", "An", "Les", "La", "Le", "Los", "El", "Der", "Die", "Das"];

// ---------------------------------------------------------------------------

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const targets = args.filter((a) => !a.startsWith("--"));
const wanted = targets.length ? targets : Object.keys(PLATFORMS);

const gamesQuery = (platformId, afterId) =>
  [
    "fields name, slug, summary, first_release_date, category, version_parent,",
    "       genres.name, cover.image_id,",
    "       involved_companies.developer, involved_companies.publisher,",
    "       involved_companies.company.name,",
    "       release_dates.region, release_dates.y, release_dates.platform;",
    `where platforms = (${platformId})`,
    `  & category = ${MAIN_GAME}`,
    "  & version_parent = null",
    `  & id > ${afterId};`,
    "sort id asc;",
    `limit ${PAGE};`,
  ].join("\n");

if (dryRun) {
  for (const slug of wanted) {
    const cfg = PLATFORMS[slug];
    if (!cfg) { console.warn(`skip unknown platform: ${slug}`); continue; }
    console.log(`\n--- ${slug} (IGDB platform ${cfg.igdb}) ---\n${gamesQuery(cfg.igdb, 0)}`);
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
  const cfg = PLATFORMS[slug];
  if (!cfg) { console.warn(`skip unknown platform: ${slug}`); continue; }

  const raw = await fetchAllGames(cfg.igdb);
  const items = raw
    .map((g) => toItem(slug, cfg, g))
    .filter(Boolean)
    .sort((a, b) => a.name.localeCompare(b.name));

  const path = join(OUT, `${slug}.json`);
  writeFileSync(
    path,
    JSON.stringify(
      { platformSlug: slug, system: cfg.system, source: "igdb", generatedAt: new Date().toISOString(), items },
      null,
      2,
    ) + "\n",
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

function toItem(platformSlug, cfg, g) {
  if (!g.name) return null;

  // US-first: keep games with a North-American (or Worldwide) release for this
  // platform. If IGDB has no per-region data at all, keep it and fall back to
  // the global first_release_date; if it has region data but none is NA, drop.
  const dates = (g.release_dates ?? []).filter(
    (d) => d.platform === cfg.igdb || d.platform == null,
  );
  const naDates = dates.filter((d) => NA_REGIONS.has(d.region));
  if (dates.length > 0 && naDates.length === 0) return null;

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

const minYear = (ds) => {
  const ys = ds.map((d) => d.y).filter((y) => Number.isFinite(y));
  return ys.length ? Math.min(...ys) : null;
};

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

const slugify = (s) =>
  s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "") // strip combining diacritics
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
