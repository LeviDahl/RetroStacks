#!/usr/bin/env node
// One-off follow-up to rgc-collection-import.mjs: the 42 items that script
// routed to `newHardwareUnmatched` (RGC doesn't distinguish kind, so these
// were deliberately excluded from the main auto-import rather than guessed
// as `kind: game`). Handled here by hand instead of generalizing the
// matcher further — a one-time list, not worth more matching machinery.
//
// Two of the 42 turned out to be misfiled games, not hardware, caught by
// the "classic"/"power pad" keywords in the hardware regex matching a real
// game title ("Metroid - Classic Series", "Short Order/Eggsplode (Power
// Pad)") rather than the physical item — handled explicitly below, not by
// broadening the regex (it already trades a few such false positives for
// catching genuine hardware, which is the safer direction).
import { readFileSync } from "fs";
import { randomUUID } from "crypto";

const SUPABASE_URL = "https://vethkqrlcacmlffuzlnx.supabase.co";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const USER_ID = "3741a221-920d-45a9-9b22-b7303cecfc15";
const execute = process.argv.includes("--execute");

if (!SERVICE_KEY) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required");
  process.exit(1);
}

async function supabaseFetchAll(path, query) {
  let all = [], offset = 0;
  while (true) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}?${query}&limit=1000&offset=${offset}`, {
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    });
    if (!res.ok) throw new Error(`${path} fetch failed: HTTP ${res.status} ${await res.text()}`);
    const rows = await res.json();
    all = all.concat(rows);
    if (rows.length < 1000) break;
    offset += 1000;
  }
  return all;
}

async function supabaseInsert(path, rows) {
  if (rows.length === 0) return;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(rows),
  });
  if (!res.ok) throw new Error(`${path} insert failed: HTTP ${res.status} ${await res.text()}`);
}

function slugify(platformSlug, name) {
  const s = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return `${platformSlug}-custom-${s}`.slice(0, 120);
}

// { rgcName, system } -> existing catalog slug — verified live against the
// actual catalog (see the conversation this was built in), not guessed:
// only listed where the RGC name unambiguously names one cataloged item.
const CONFIDENT_MATCHES = {
  "NES::NES Advantage Controller": "nes-advantage",
  "NES::NES Console Top Loader": "nes-top-loader",
  "NES::Zapper Light Gun": "nes-zapper",
  "N64::N64 Console": "nus-001",
  "SNES::Super Nintendo Console": "sns-001", // ambiguous vs SNS-101 Jr — defaults to the original model
  "Genesis::Sega Genesis Console": "gen-model-1", // Model 2/3 called out separately by RGC, so bare = Model 1 by elimination
  "Genesis::Sega Genesis Model 2 Console": "gen-model-2",
  "Genesis::Sega 6 Button Controller": "gen-6button",
  "Dreamcast::Sega Dreamcast Console": "hkt-3020", // only one Dreamcast console variant cataloged
  "Playstation 1::PSOne Console": "ps-one",
  "Playstation 1::PS1 Console": "scph-1001",
  "Atari 2600::Atari 2600 Joystick": "2600-cx40",
};

// Everything else: new custom item, classified game/console/accessory.
const NEW_ITEMS = [
  { system: "NES", name: "Dogbone Controller", kind: "accessory" },
  { system: "NES", name: "Game Genie", kind: "accessory" },
  { system: "NES", name: "NES Classic Mini", kind: "console" },
  { system: "NES", name: "NES Classic Mini Controller", kind: "accessory" },
  { system: "NES", name: "NES Console", kind: "console" }, // distinct listing from "NES Control Deck" — RGC gave no model detail, kept separate rather than assumed
  { system: "NES", name: "NES Console Sports Set", kind: "console", hasManual: true },
  { system: "NES", name: "NES Controller", kind: "accessory" },
  { system: "NES", name: "NES Satellite", kind: "accessory" },
  { system: "NES", name: "Nintendo NES Controller 2 Pack", kind: "accessory" },
  { system: "NES", name: "Power Pad", kind: "accessory" },
  { system: "N64", name: "Game Organizer Drawer (24 slots)", kind: "accessory" },
  { system: "N64", name: "Gameboy Transfer Pak", kind: "accessory" },
  { system: "N64", name: "Gameshark Pro", kind: "accessory" },
  { system: "N64", name: "N64 Console Gold", kind: "console" },
  { system: "N64", name: "N64 Controller Gold", kind: "accessory" },
  { system: "N64", name: "N64 Controller Green", kind: "accessory" },
  { system: "N64", name: "N64 Controller Pak", kind: "accessory" },
  { system: "SNES", name: "SNES Classic Mini", kind: "console" },
  { system: "SNES", name: "Super Nintendo Controller", kind: "accessory" },
  { system: "Genesis", name: "Game Genie", kind: "accessory" },
  { system: "Genesis", name: "Sega 3 Button Controller", kind: "accessory" },
  { system: "Genesis", name: "Sega Genesis CDx Console", kind: "console" },
  { system: "Genesis", name: "Sega Genesis Model 3 Console", kind: "console" },
  { system: "Playstation 2", name: "PlayStation 2 Console", kind: "console" }, // Fat vs Slim not specified by RGC, not guessed
  { system: "Atari 2600", name: "Atari 2600 Console", kind: "console" }, // 4-Switch vs Heavy Sixer not specified, not guessed
  { system: "GameCube", name: "GameCube Console Black", kind: "console" }, // catalog only has Indigo
  { system: "GameCube", name: "GameCube Console Platinum", kind: "console" },
  { system: "Playstation 1", name: "Playstation Classic", kind: "console" },
];

const SYSTEM_TO_PLATFORM = {
  NES: "nes", N64: "n64", SNES: "snes", Genesis: "genesis", "Atari 2600": "atari-2600",
  "Game Boy": "game-boy", Dreamcast: "dreamcast", GameCube: "gamecube",
  "Playstation 2": "ps2", "Playstation 1": "playstation",
};

// The two miscategorized games, resolved directly rather than through the
// hardware path.
const RECLASSIFIED_GAMES = [
  // "Metroid - Classic Series" is a real NES reissue variant — matches the
  // catalog's base "Metroid" (nes-metroid) with a variant tag, the same
  // shape as the "(5 screw)"-style variants the main import already handles.
  { system: "NES", rgcName: "Metroid - Classic Series", resolvedSlug: "nes-metroid" },
  // "Short Order/Eggsplode (Power Pad)" is the catalog's existing
  // "Short Order / Egg-splode!" — missed by the main import's matcher only
  // because "Eggsplode" (RGC) vs "Egg-splode" (catalog) tokenize
  // differently once the hyphen splits into two words.
  { system: "NES", rgcName: "Short Order/Eggsplode (Power Pad)", resolvedSlug: "nes-short-order-egg-splode" },
];

async function main() {
  // Real box/manual completeness from the original RGC scrape — the same
  // source rgc-collection-import.mjs's newHardwareUnmatched came from —
  // rather than guessed defaults.
  const completeness = JSON.parse(readFileSync("api/data/rgc-import-report.json", "utf8")).newHardwareUnmatched
    .reduce((map, r) => ({ ...map, [`${r.system}::${r.name}`]: { box: r.box, manual: r.manual } }), {});

  const existingCollection = await supabaseFetchAll(
    "collection_items",
    `user_id=eq.${USER_ID}&deleted_at=is.null&select=catalog_slug,status`
  );
  const alreadyTracked = new Set(existingCollection.map((r) => `${r.catalog_slug}::owned`));

  const confidentRows = Object.entries(CONFIDENT_MATCHES).map(([key, slug]) => {
    const [system, name] = key.split("::");
    return { system, name, resolvedSlug: slug, ...(completeness[key] ?? { box: false, manual: false }) };
  });

  const newCatalogRows = NEW_ITEMS.map((item) => ({
    slug: slugify(SYSTEM_TO_PLATFORM[item.system], item.name),
    platform_slug: SYSTEM_TO_PLATFORM[item.system],
    kind: item.kind,
    name: item.name,
    owner_user_id: USER_ID,
    summary: "",
    submitted_for_public: false,
    updated_at: new Date().toISOString(),
  }));

  console.log(`${confidentRows.length} confident matches, ${newCatalogRows.length} new hardware items, ${RECLASSIFIED_GAMES.length} reclassified games`);

  const allEntries = [
    ...confidentRows,
    ...newCatalogRows.map((r, i) => ({
      system: NEW_ITEMS[i].system, name: r.name, resolvedSlug: r.slug,
      ...(completeness[`${NEW_ITEMS[i].system}::${NEW_ITEMS[i].name}`] ?? { box: false, manual: false }),
    })),
    ...RECLASSIFIED_GAMES.map((r) => ({
      system: r.system, name: r.rgcName, resolvedSlug: r.resolvedSlug,
      ...(completeness[`${r.system}::${r.rgcName}`] ?? { box: false, manual: false }),
    })),
  ];

  const toInsert = allEntries.filter((e) => !alreadyTracked.has(`${e.resolvedSlug}::owned`));
  console.log(`${toInsert.length} collection_items to add (${allEntries.length - toInsert.length} already tracked)`);

  if (!execute) {
    console.log("(dry run — pass --execute to write)");
    for (const e of toInsert) console.log(" ", e.system, "::", e.name, "->", e.resolvedSlug);
    return;
  }

  await supabaseInsert("catalog_items", newCatalogRows);

  const now = new Date().toISOString();
  const collectionRows = toInsert.map((e) => ({
    id: randomUUID(),
    user_id: USER_ID,
    catalog_slug: e.resolvedSlug,
    status: "owned",
    condition: "good",
    completeness: e.box && e.manual ? "completeInBox" : e.box ? "boxedNoManual" : "loose",
    has_box: e.box,
    has_manual: e.manual,
    has_inserts: false,
    has_original_packaging: false,
    grading_company: "none",
    notes: "",
    date_added: now,
    updated_at: now,
  }));
  await supabaseInsert("collection_items", collectionRows);
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
