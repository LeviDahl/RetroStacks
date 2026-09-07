// Data source: the hand-curated set (api/data/curated.json — the source of truth,
// synced into the app bundle by ../sync-seed.mjs) merged with the bulk catalogs
// in api/data/generated/*.json (produced by ../ingest/libretro.mjs or igdb.mjs).
//
// Curated wins: platforms + consoles/accessories come only from curated, and a
// generated game is dropped when a curated game on the same platform has a
// matching (normalized) title — so the curated entry keeps its slug, prices,
// summary, and verified art.
//
//   loadCatalog(): Promise<{ platforms, items }>  — shapes documented inline below.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DATA = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data");

export const name = "local-file";

const normalize = (s) =>
  s
    .toLowerCase()
    .replace(/\([^)]*\)/g, "")
    .replace(/\b(the|a|an)\b/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();

export async function loadCatalog() {
  const curated = JSON.parse(readFileSync(join(DATA, "curated.json"), "utf8"));

  // curated titles already covered, per platform
  const curatedTitles = {};
  for (const it of curated.items) {
    if (it.kind !== "game") continue;
    (curatedTitles[it.platformSlug] ??= new Set()).add(normalize(it.name));
  }

  const generatedItems = [];
  const genDir = join(DATA, "generated");
  if (existsSync(genDir)) {
    for (const file of readdirSync(genDir).filter((f) => f.endsWith(".json"))) {
      const gen = JSON.parse(readFileSync(join(genDir, file), "utf8"));
      for (const it of gen.items) {
        if (curatedTitles[it.platformSlug]?.has(normalize(it.name))) continue;
        generatedItems.push(it);
      }
    }
  }

  return {
    platforms: curated.platforms,
    items: [...curated.items, ...generatedItems],
  };
}
