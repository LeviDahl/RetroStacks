// Pricing enricher: refresh prices from the PriceCharting API. SKELETON.
//
// The build calls this after loading the catalog. It returns a Map<slug, patch>
// where patch may set priceLoose / priceComplete / priceSealed / priceGraded /
// salesVolumeYearly and (optionally) richer `points` + `primaryProvider` that
// build.mjs will fold into each item's PriceGuide. Items not in the Map keep
// their seed prices.
//
// Notes (from api-documentation): prices are integer pennies; dates YYYY-MM-DD;
// hard cap of 1 request/second; needs a paid token in PRICECHARTING_TOKEN.
// Prefer the nightly CSV over per-item calls once on the Legendary tier.

export const name = "pricecharting";

export async function refreshPrices(items) {
  const token = process.env.PRICECHARTING_TOKEN;
  if (!token) return new Map();

  throw new Error(
    "pricecharting enricher not implemented — see api/build/pricing/pricecharting.mjs",
  );

  // Sketch (per-item, throttled):
  //
  // const out = new Map();
  // for (const it of items) {
  //   const q = it.upc
  //     ? `upc=${encodeURIComponent(it.upc)}`
  //     : `q=${encodeURIComponent(`${it.name} ${it.platformSlug}`)}`;
  //   const r = await fetch(`https://www.pricecharting.com/api/product?t=${token}&${q}`);
  //   const p = await r.json();
  //   if (p.status !== "error" && p.id) {
  //     out.set(it.slug, {
  //       priceLoose: cents(p["loose-price"]),
  //       priceComplete: cents(p["cib-price"]),
  //       priceSealed: cents(p["new-price"]),
  //       priceGraded: cents(p["graded-price"]),
  //       salesVolumeYearly: Number(p["sales-volume"]) || null,
  //       primaryProvider: "pricecharting",
  //     });
  //   }
  //   await sleep(1100); // 1 req/sec cap
  // }
  // return out;
}

// const cents = (n) => (n == null ? null : n / 100);
// const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
