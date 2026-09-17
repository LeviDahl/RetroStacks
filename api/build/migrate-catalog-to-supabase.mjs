#!/usr/bin/env node
// One-time (and re-runnable) migration: upserts the built catalog
// (dist/v1/catalog.json) into Supabase's public.catalog_items table as
// *public* rows (owner_user_id = null) — Phase 2 of the plan to make
// Supabase the real source of truth for the catalog, not just a static
// JSON feed. See supabase/schema.sql's "Phase 2" section for the table/RLS/
// function this depends on; run that in the SQL Editor first if you haven't.
//
// Run `node api/build/build.mjs` first so dist/v1/catalog.json is current —
// this script doesn't rebuild it for you.
//
//   SUPABASE_SERVICE_ROLE_KEY=…  node api/build/migrate-catalog-to-supabase.mjs
//   node api/build/migrate-catalog-to-supabase.mjs --dry-run     # map + batch, no network calls
//   node api/build/migrate-catalog-to-supabase.mjs --limit 20    # only the first N items, for testing
//
// Platforms are NOT migrated — still the small, bundled, local-only set the
// app already ships with (see the schema's own note on why). Only `items`
// (games/consoles/accessories) become catalog_items rows.
//
// Uses upsert_public_catalog_items(jsonb), not PostgREST's own upsert
// (?on_conflict=slug) — confirmed live 2026-09-17 that PostgREST can't
// target catalog_items_public_slug_idx (a *partial* unique index) through
// its on_conflict query param; see that function's comment in schema.sql.
// The service role key is required specifically because that function is
// revoked from every other role — this script can't work with the app's
// own anon/publishable key.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const CATALOG_PATH = join(ROOT, "api", "dist", "v1", "catalog.json");
const SUPABASE_URL = "https://vethkqrlcacmlffuzlnx.supabase.co";
const BATCH_SIZE = 500;

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const limitIdx = args.indexOf("--limit");
const limit = limitIdx >= 0 ? Number(args[limitIdx + 1]) : undefined;

const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!dryRun && !serviceRoleKey) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required (unless --dry-run).");
  process.exit(1);
}

function toRow(item) {
  return {
    slug: item.slug,
    platform_slug: item.platformSlug,
    kind: item.kind,
    name: item.name,
    variant: item.variant ?? null,
    release_year_na: item.releaseYearNA ?? null,
    manufacturer_or_publisher: item.manufacturerOrPublisher ?? null,
    developer: item.developer ?? null,
    genre: item.genre ?? null,
    upc: item.upc ?? null,
    summary: item.summary ?? "",
    image_name: item.imageName ?? null,
    image_url_string: item.imageURL ?? null,
    image_credit: item.imageCredit ?? null,
    image_license: item.imageLicense ?? null,
  };
}

async function upsertBatch(rows) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/upsert_public_catalog_items`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ items: rows }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`batch upsert failed: HTTP ${res.status} — ${body}`);
  }
}

async function main() {
  const feed = JSON.parse(readFileSync(CATALOG_PATH, "utf8"));
  let items = feed.items;
  if (limit) items = items.slice(0, limit);

  const rows = items.map(toRow);
  console.log(`${rows.length} items mapped from ${feed.items.length} in the catalog feed.`);

  if (dryRun) {
    console.log("--dry-run: no network calls. Sample row:");
    console.log(JSON.stringify(rows[0], null, 2));
    console.log(`Would send ${Math.ceil(rows.length / BATCH_SIZE)} batch(es) of up to ${BATCH_SIZE}.`);
    return;
  }

  let sent = 0;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    await upsertBatch(batch);
    sent += batch.length;
    console.log(`  upserted ${sent}/${rows.length}`);
  }
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
