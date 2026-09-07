// Pricing enricher: refresh prices from the PriceCharting API.
//
// build.mjs calls refreshPrices(items) after loading the catalog and folds the
// returned Map<slug, patch> into each item (priceLoose / priceComplete /
// priceSealed / priceGraded / salesVolumeYearly, plus primaryProvider). Items
// not in the Map keep their seed prices.
//
// PriceCharting API notes (api-documentation): prices are integer pennies;
// dates YYYY-MM-DD; hard cap 1 request/second; needs a paid token.
//
// Guards, because this hits a paid third-party API on a 1 req/sec leash:
//   PRICECHARTING_TOKEN    required — the API token.
//   PRICECHARTING_ENABLE   required — must be "1"; without it this is a no-op
//                          even when a token is present (so setting the token
//                          in CI can't silently start a 60-minute job).
//   PRICECHARTING_MAX      per-run cap on API calls (default 400). Runs are
//                          additive night to night: only items with no price
//                          yet are queried, most-recently-released first, so
//                          coverage fills in over several nights.
//   PRICECHARTING_DELAY_MS spacing between calls (default 1100).

export const name = "pricecharting";

const ENDPOINT = "https://www.pricecharting.com/api/product";

export async function refreshPrices(items) {
  const token = process.env.PRICECHARTING_TOKEN;
  const out = new Map();

  if (!token) return out;
  if (process.env.PRICECHARTING_ENABLE !== "1") {
    console.log("pricing: PRICECHARTING_ENABLE != 1 — skipping PriceCharting enrichment");
    return out;
  }

  const max = clampInt(process.env.PRICECHARTING_MAX, 400, 1, 20000);
  const delayMs = clampInt(process.env.PRICECHARTING_DELAY_MS, 1100, 250, 10000);

  // Only items still missing a price, newest first (better hit rate, and the
  // stuff people are most likely to be pricing).
  const queue = items
    .filter((it) => !hasAnyPrice(it))
    .sort((a, b) => (b.releaseYearNA ?? 0) - (a.releaseYearNA ?? 0))
    .slice(0, max);

  console.log(
    `pricing: PriceCharting enrichment on — ${queue.length} item(s) this run ` +
      `(cap ${max}, ${delayMs}ms apart)`,
  );

  let ok = 0;
  let failed = 0;
  for (const it of queue) {
    try {
      const patch = await fetchOne(it, token);
      if (patch) {
        out.set(it.slug, patch);
        ok++;
      }
    } catch (err) {
      failed++;
      if (failed <= 5) console.warn(`pricing: ${it.slug} — ${err.message}`);
    }
    await sleep(delayMs);
  }

  console.log(`pricing: PriceCharting matched ${ok}/${queue.length} (${failed} errored)`);
  return out;
}

// --- internals --------------------------------------------------------------

async function fetchOne(item, token) {
  const params = new URLSearchParams({ t: token });
  if (item.upc) params.set("upc", item.upc);
  else params.set("q", `${item.name} ${item.platformSlug}`.trim());

  const res = await fetch(`${ENDPOINT}?${params}`, {
    headers: { accept: "application/json" },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);

  const body = await res.json();
  if (!body || body.status === "error" || !body.id) return null;

  const patch = dropNullish({
    priceLoose: cents(body["loose-price"]),
    priceComplete: cents(body["cib-price"]),
    priceSealed: cents(body["new-price"]),
    priceGraded: cents(body["graded-price"]),
    salesVolumeYearly: intOrNull(body["sales-volume"]),
  });
  if (Object.keys(patch).length === 0) return null;

  patch.primaryProvider = "pricecharting";
  return patch;
}

const hasAnyPrice = (it) =>
  it.priceLoose != null ||
  it.priceComplete != null ||
  it.priceSealed != null ||
  it.priceGraded != null;

// PriceCharting sends integer pennies; the feed carries dollars as numbers.
const cents = (n) => (n == null || n === "" ? null : Number(n) / 100);
const intOrNull = (n) => {
  const v = Number(n);
  return Number.isFinite(v) && v > 0 ? Math.round(v) : null;
};

function dropNullish(obj) {
  return Object.fromEntries(Object.entries(obj).filter(([, v]) => v != null));
}

function clampInt(raw, fallback, lo, hi) {
  const v = Number.parseInt(raw ?? "", 10);
  if (!Number.isFinite(v)) return fallback;
  return Math.min(Math.max(v, lo), hi);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
