// Data source: Supabase / Postgres. SKELETON — not wired.
//
//   SOURCE=supabase SUPABASE_URL=… SUPABASE_SERVICE_KEY=… node api/build/build.mjs
//
// Same output shape as local-file.mjs. Either hit PostgREST directly (fetch) or
// `npm i @supabase/supabase-js`. Use the service key here (build runs in CI, not
// the client) and keep row-level security for the app's own reads.

export const name = "supabase";

export async function loadCatalog() {
  throw new Error(
    "supabase source not implemented — see api/build/sources/supabase.mjs",
  );

  // Sketch (PostgREST, no SDK):
  //
  // const base = `${process.env.SUPABASE_URL}/rest/v1`;
  // const headers = {
  //   apikey: process.env.SUPABASE_SERVICE_KEY,
  //   Authorization: `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
  // };
  // const get = (t) => fetch(`${base}/${t}?select=*`, { headers }).then((r) => r.json());
  // const [platforms, items] = await Promise.all([get("platform"), get("catalog_item")]);
  // return { platforms: platforms.map(rowToPlatform), items: items.map(rowToItem) };
}
