// Data source: MySQL (e.g. a GoDaddy-hosted DB). SKELETON — not wired.
//
// Fill in the queries, `npm i mysql2`, then run the build with:
//   SOURCE=mysql DB_HOST=… DB_USER=… DB_PASS=… DB_NAME=… node api/build/build.mjs
//
// The job is only to return the shape local-file.mjs documents. Suggested tables:
//   platform(slug PK, name, short_name, manufacturer, generation,
//            release_year_na, discontinued_year_na, summary, icon_system_name,
//            regions /* csv or json */)
//   catalog_item(slug PK, platform_slug FK, kind, name, variant, release_year_na,
//                manufacturer_or_publisher, developer, genre, upc, summary,
//                image_url, image_credit, image_license,
//                price_loose, price_complete, price_sealed, price_graded,
//                sales_volume_yearly)

export const name = "mysql";

export async function loadCatalog() {
  throw new Error(
    "mysql source not implemented — see api/build/sources/mysql.mjs",
  );

  // Sketch:
  //
  // const mysql = await import("mysql2/promise");
  // const db = await mysql.createConnection({
  //   host: process.env.DB_HOST, user: process.env.DB_USER,
  //   password: process.env.DB_PASS, database: process.env.DB_NAME,
  // });
  // const [platformRows] = await db.query("SELECT * FROM platform");
  // const [itemRows] = await db.query("SELECT * FROM catalog_item");
  // await db.end();
  // return {
  //   platforms: platformRows.map(rowToPlatform),
  //   items: itemRows.map(rowToItem),
  // };
}
