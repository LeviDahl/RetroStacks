#!/usr/bin/env node
// One-off repair: a re-ingest + migrate-catalog-to-supabase.mjs run
// unconditionally reset `deleted_at = null` on every re-synced slug (see
// upsert_public_catalog_items's old `do update set ... deleted_at = null`
// — fixed in supabase/schema.sql, but the fix only prevents this
// happening *again*; it doesn't undo the exclusions it already reverted).
// This re-applies every exclusion the pricecharting-catalog-match.mjs
// reports already on disk (api/data/pricecharting-match-*.json, gitignored
// but not deleted) recorded — no PriceCharting API calls needed, this is
// pure re-application of a decision already made and verified earlier.
//
//   SUPABASE_SERVICE_ROLE_KEY=…  node api/build/restore-pricecharting-exclusions.mjs
//   node api/build/restore-pricecharting-exclusions.mjs --dry-run
import { readdirSync, readFileSync } from "fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DATA_DIR = join(ROOT, "api", "data");
const SUPABASE_URL = "https://vethkqrlcacmlffuzlnx.supabase.co";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dryRun = process.argv.includes("--dry-run");

if (!dryRun && !SERVICE_KEY) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required (unless --dry-run).");
  process.exit(1);
}

async function excludeSlugs(slugs) {
  const now = new Date().toISOString();
  for (let i = 0; i < slugs.length; i += 50) {
    const batch = slugs.slice(i, i + 50);
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog_items?slug=in.(${batch.join(",")})&owner_user_id=is.null`,
      {
        method: "PATCH",
        headers: {
          apikey: SERVICE_KEY,
          Authorization: `Bearer ${SERVICE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ deleted_at: now }),
      }
    );
    if (!res.ok) throw new Error(`exclude batch failed: HTTP ${res.status} ${await res.text()}`);
  }
}

async function main() {
  const reportFiles = readdirSync(DATA_DIR).filter((f) => f.startsWith("pricecharting-match-") && f.endsWith(".json"));
  console.log(`${reportFiles.length} report files found`);

  let totalSlugs = 0;
  for (const file of reportFiles) {
    const report = JSON.parse(readFileSync(join(DATA_DIR, file), "utf8"));
    const slugs = report.results
      .filter((r) => r.suggestion === "exclude-homebrew" || r.suggestion === "exclude-not-found")
      .map((r) => r.slug);
    totalSlugs += slugs.length;
    console.log(`  ${report.platform}: ${slugs.length} slugs to re-exclude`);

    if (dryRun) continue;
    await excludeSlugs(slugs);
  }

  console.log(`\n${dryRun ? "Would re-exclude" : "Re-excluded"} ${totalSlugs} items total.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
