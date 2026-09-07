#!/usr/bin/env node
// Copies the curated catalog into the app bundle as the first-launch seed.
//
//   node api/build/sync-seed.mjs
//
// api/data/curated.json is the hand-authored source of truth for the ~66 curated
// entries. The app decodes apple/RetroStacks/Resources/CatalogSeed.json on first
// launch (SampleData → CatalogSeedStore); this keeps the two in lockstep so
// there's one place to edit. Run after touching curated.json; commit both.
//
// Replaces the old api/build/export-catalog.swift (which went the other way:
// Swift literals → JSON).

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, "..", "data", "curated.json");
const DEST = join(HERE, "..", "..", "apple", "RetroStacks", "Resources", "CatalogSeed.json");

const curated = JSON.parse(readFileSync(SRC, "utf8"));

const platforms = [...curated.platforms].sort(
  (a, b) => a.generation - b.generation || a.name.localeCompare(b.name),
);
const items = [...curated.items].sort((a, b) => a.slug.localeCompare(b.slug));

// No generatedAt — a stable file keeps git diffs to real content changes.
const seed = { platforms, items };

writeFileSync(DEST, JSON.stringify(seed, null, 2) + "\n");
console.log(`sync-seed: ${platforms.length} platforms, ${items.length} items -> ${DEST.replace(join(HERE, "..", "..") + "/", "")}`);
