#!/usr/bin/env node
// Pulls a US game catalog per platform from libretro-database (No-Intro / Redump
// lists + genre/year/publisher/developer metadata) and writes
// api/data/generated/<platform>.json. Zero deps.
//
//   node api/build/ingest/libretro.mjs            # all platforms below
//   node api/build/ingest/libretro.mjs nes snes   # just these
//
// build.mjs (via sources/local-file.mjs) then merges these with the hand-curated
// api/data/curated.json — curated wins on any title it also covers.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data", "generated");
const RAW = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat";

// our platform slug -> libretro system folder + dat family
const PLATFORMS = {
  "atari-2600":  { sys: "Atari - 2600",                               family: "no-intro" },
  "nes":         { sys: "Nintendo - Nintendo Entertainment System",    family: "no-intro" },
  "snes":        { sys: "Nintendo - Super Nintendo Entertainment System", family: "no-intro" },
  "n64":         { sys: "Nintendo - Nintendo 64",                      family: "no-intro" },
  "game-boy":    { sys: "Nintendo - Game Boy",                         family: "no-intro" },
  "genesis":     { sys: "Sega - Mega Drive - Genesis",                 family: "no-intro" },
  "playstation": { sys: "Sony - PlayStation",                          family: "redump" },
  "ps2":         { sys: "Sony - PlayStation 2",                        family: "redump" },
  "dreamcast":   { sys: "Sega - Dreamcast",                            family: "redump" },
  "gamecube":    { sys: "Nintendo - GameCube",                         family: "redump" },
};

const ARTICLES = ["The", "A", "An", "Les", "La", "Le", "Los", "El", "Der", "Die", "Das"];

const DROP =
  /\((Proto|Beta|Demo|Sample|Aftermarket|Unl|Pirate|Hack|Debug|Test|Program|Competition Cart|Kiosk|Rev X|GameCube|Virtual Console|Switch Online|NP|Promo|Retro-Bit|iam8bit|Limited Run|Analogue|Evercade|Classic Edition|Namco Museum|Steam|GOG)/i;
const MULTICART = /\b\d+[-\s]?in[-\s]?1\b/i;
const KEEP_REGION = /\((USA|World)\b|\(USA,/;

async function fetchDat(family, sys) {
  const url = `${RAW}/${family}/${encodeURIComponent(sys)}.dat`;
  const r = await fetch(url);
  return r.ok ? r.text() : null;
}

// ClrMamePro: split into `game ( ... )` blocks, pull simple `key "value"` pairs
// and every `crc XXXXXXXX`.
function parseGames(text) {
  if (!text) return [];
  const out = [];
  const re = /game\s*\(([\s\S]*?)\n\)/g;
  let m;
  while ((m = re.exec(text))) {
    const body = m[1];
    const field = (k) => {
      const f = body.match(new RegExp(`\\b${k}\\s+"([^"]*)"`));
      return f ? f[1] : null;
    };
    const crcs = [...body.matchAll(/\bcrc\s+([0-9A-Fa-f]{8})\b/g)].map((c) => c[1].toUpperCase());
    out.push({
      name: field("name"),
      comment: field("comment"),
      region: field("region"),
      genre: field("genre"),
      releaseyear: field("releaseyear"),
      publisher: field("publisher"),
      developer: field("developer"),
      crcs,
    });
  }
  return out;
}

// "Legend of Zelda, The (USA) (Disc 1) (Rev 1)" -> "The Legend of Zelda"
function cleanTitle(name) {
  let t = name.replace(/\s*\([^)]*\)/g, "").replace(/\s*\[[^\]]*\]/g, "").trim();
  t = t.replace(/\s*-\s*(Disc|Disk|CD)\s*\d+\s*$/i, "").trim();
  for (const art of ARTICLES) {
    const suffix = `, ${art}`;
    if (t.endsWith(suffix)) {
      t = `${art} ${t.slice(0, -suffix.length)}`;
      break;
    }
  }
  return t.replace(/\s+/g, " ").trim();
}

function slugify(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function ingestOne(slug, { sys, family }, meta) {
  const list = parseGames(meta.list);
  const byCrc = {};
  for (const family of ["genre", "releaseyear", "publisher", "developer"]) {
    for (const g of parseGames(meta[family])) {
      for (const crc of g.crcs) {
        byCrc[crc] ??= {};
        if (g[family]) byCrc[crc][family] = g[family];
      }
    }
  }

  const seen = new Set();
  const items = [];
  let droppedNoMeta = 0;
  for (const g of list) {
    if (!g.name) continue;
    if (DROP.test(g.name) || MULTICART.test(g.name)) continue;
    if (!KEEP_REGION.test(g.name) && g.region !== "USA" && g.region !== "World") continue;

    const md = g.crcs.map((c) => byCrc[c]).find(Boolean) || {};
    // Licensed commercial releases are essentially all in libretro's
    // genre/publisher/year metadata; bootlegs / homebrew / bad dumps are not.
    // (Disc systems have no such metadata in libretro-database — skip the gate.)
    if (family === "no-intro" && !md.releaseyear && !md.publisher && !md.genre) {
      droppedNoMeta++;
      continue;
    }

    const title = cleanTitle(g.name);
    if (!title) continue;
    const itemSlug = `${slug}-${slugify(title)}`;
    if (seen.has(itemSlug)) continue; // first spelling wins (revisions, .unh dupes)
    seen.add(itemSlug);

    const year = parseInt(md.releaseyear || "", 10);

    items.push({
      slug: itemSlug,
      platformSlug: slug,
      kind: "game",
      name: title,
      releaseYearNA: Number.isFinite(year) ? year : null,
      manufacturerOrPublisher: md.publisher || null,
      developer: md.developer || null,
      genre: md.genre || null,
      imageURL:
        `https://thumbnails.libretro.com/${encodeURIComponent(sys)}` +
        `/Named_Boxarts/${encodeURIComponent(g.name)}.png`,
      imageCredit: "Box art via Libretro thumbnails",
      imageLicense: "Publisher artwork",
      source: `libretro/${family}`,
    });
  }
  items.sort((a, b) => a.name.localeCompare(b.name));
  if (droppedNoMeta) console.log(`  (${droppedNoMeta} dropped — no metadata / likely unlicensed)`);
  return items;
}

const wanted = process.argv.slice(2);
const targets = wanted.length ? wanted : Object.keys(PLATFORMS);

mkdirSync(OUT, { recursive: true });
for (const slug of targets) {
  const cfg = PLATFORMS[slug];
  if (!cfg) {
    console.warn(`skip unknown platform: ${slug}`);
    continue;
  }
  const [list, genre, releaseyear, publisher, developer] = await Promise.all([
    fetchDat(cfg.family, cfg.sys),
    fetchDat("genre", cfg.sys),
    fetchDat("releaseyear", cfg.sys),
    fetchDat("publisher", cfg.sys),
    fetchDat("developer", cfg.sys),
  ]);
  if (!list) {
    console.warn(`no ${cfg.family} dat for ${slug} (${cfg.sys})`);
    continue;
  }
  const items = ingestOne(slug, cfg, { list, genre, releaseyear, publisher, developer });
  const path = join(OUT, `${slug}.json`);
  writeFileSync(
    path,
    JSON.stringify({ platformSlug: slug, system: cfg.sys, generatedAt: new Date().toISOString(), items }, null, 2) + "\n",
  );
  console.log(`${slug}: ${items.length} games -> data/generated/${slug}.json`);
}
