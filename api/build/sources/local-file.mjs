// Data source: the checked-in canonical file (api/data/catalog.json), which is
// itself regenerated from the app's SampleData by ../export-catalog.swift.
//
// This is the reference implementation of the source interface. To move the
// backend to a database later, add a sibling (mysql.mjs / supabase.mjs) that
// exports the same `loadCatalog()` and select it with `SOURCE=mysql`.
//
//   loadCatalog(): Promise<{
//     platforms: Array<{ slug, name, shortName, manufacturer, generation,
//                        releaseYearNA?, discontinuedYearNA?, summary,
//                        iconSystemName, regions: string[] }>,
//     items: Array<{ slug, platformSlug, kind, name, variant?, releaseYearNA?,
//                    manufacturerOrPublisher?, developer?, genre?, upc?, summary,
//                    imageURL?, imageCredit?, imageLicense?,
//                    priceLoose?, priceComplete?, priceSealed?, priceGraded?,
//                    salesVolumeYearly? }>
//   }>

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DATA = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data", "catalog.json");

export const name = "local-file";

export async function loadCatalog() {
  const feed = JSON.parse(readFileSync(DATA, "utf8"));
  return { platforms: feed.platforms, items: feed.items };
}
