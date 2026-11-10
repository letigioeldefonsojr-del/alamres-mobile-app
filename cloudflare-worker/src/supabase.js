// supabase-chatbot-products
// Supabase access for the chatbot's list_products tool.
//
// Products moved from Firestore to Supabase on the Flutter app side (see
// kUseSupabaseProducts and lib/services/supabase_products.dart there) -
// this chatbot has to follow that move too, or its product lookups keep
// reading Firestore's `products` collection, which that migration left
// frozen with old sample data that no longer matches reality.
//
// Same backend as the app: everything goes through the one `store-api`
// Supabase Edge Function. Auth works the same way too - Supabase verifies
// the caller's Firebase ID token server-side itself (never verified
// client-side, or here), so this just forwards the very token this Worker
// already verified moments ago (see index.js) as the x-firebase-token
// header, rather than needing any Supabase credential of its own beyond
// the public, already-shipped-in-the-app publishable key
// (SUPABASE_PUBLISHABLE_KEY in wrangler.toml - not a secret).

// The full product catalog, cached briefly in memory - same reasoning as
// firestore.js's old productsCache: a sari-sari store's catalog doesn't
// change fast enough within one conversation to justify a fresh network
// round trip on every single tool call.
//
// 5 minutes, not 60s: at ~4,500 products and 1,000/page, a cold cache
// means up to 5 SEQUENTIAL round trips to store-api just to build this
// list, on top of the two Claude API calls either side of the tool call
// (deciding to use it, then writing the final reply). Stacked together
// that can run past the app's own chat request timeout (chat_service.dart)
// for an ordinary "how much is X" question - confirmed in practice: a
// plain "hi" (no tool call) replies fine, but a price question right
// after a cold cache can time out. Same tradeoff as BannerRepository's
// 5-minute TTL on the Flutter side - a stale product list for a few extra
// minutes is a much smaller problem than the chatbot failing outright.
let productsCache = null; // { products, expiresAt }
const PRODUCTS_CACHE_MS = 5 * 60_000;

async function callStoreApi(env, firebaseToken, body) {
  const res = await fetch(`${env.SUPABASE_URL}/functions/v1/store-api`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      'x-firebase-token': firebaseToken,
    },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => null);
  if (!data || data.ok !== true) {
    throw new Error(`Supabase store-api error: ${(data && data.error) || res.status}`);
  }
  return data;
}

function formatPeso(value) {
  return `₱${Number(value).toFixed(2)}`;
}

// Converts one Supabase `products` row (snake_case, numeric prices) into
// the same shape this Worker's own summarizeProduct() / isDiscountActive()
// / effectivePrice() (index.js) already expect - peso-formatted price
// strings, `stockCount`, `wholesalePrice`, etc. - the same shape Firestore
// docs used to come back as. This is a near-exact mirror of
// productFromRow() in the app's lib/services/supabase_products.dart, so a
// product looks identical to the chatbot whether it reads it or the app
// does. `extra` is spread in first (it carries the "leftover" fields this
// Worker still reads directly - bestSeller, discountPercent,
// discountStart/End, originalPrice) so the explicit fields below always
// win on any accidental name collision.
function productFromRow(row) {
  const extra = row.extra && typeof row.extra === 'object' ? row.extra : {};
  const variantPrices =
    row.variant_prices && typeof row.variant_prices === 'object' ? row.variant_prices : {};

  const flavors = Array.isArray(row.flavors)
    ? row.flavors.map((f) => {
        const wholesale =
          f.name != null && typeof variantPrices[f.name] === 'number'
            ? variantPrices[f.name]
            : null;
        return {
          name: f.name,
          price: typeof f.price === 'number' ? formatPeso(f.price) : f.price,
          stock: f.stock,
          available: f.available !== false,
          ...(wholesale != null ? { wholesalePrice: formatPeso(wholesale) } : {}),
        };
      })
    : [];

  return {
    ...extra,
    id: row.id,
    name: row.name,
    category: row.category,
    price: typeof row.price === 'number' ? formatPeso(row.price) : '₱0.00',
    ...(typeof row.wholesale_price === 'number'
      ? { wholesalePrice: formatPeso(row.wholesale_price) }
      : {}),
    stockCount: row.stock_count,
    available: row.available !== false,
    flavors,
  };
}

// 1000 per page, same default the app uses.
const PAGE_SIZE = 1000;

// How many pages to request AT ONCE on a cold cache, before falling back
// to one-at-a-time. Each page's offset (0, 1000, 2000, ...) doesn't
// depend on what any other page returned, so there's no real reason to
// wait for page N before asking for page N+1 - requesting pages one at a
// time would mean up to 5 SEQUENTIAL round trips at today's ~4,500
// products (see the latency comment on PRODUCTS_CACHE_MS below). 8 pages
// (8,000 products) covers that with real headroom to grow before this
// needs raising.
const PARALLEL_PAGE_BURST = 8;

// Pages through app_list_products (same action the app itself calls) and
// caches the whole, converted catalog in memory for PRODUCTS_CACHE_MS.
// [firebaseToken] is the raw, already-verified Firebase ID token string
// from the current request (see index.js) - Supabase does its own
// verification of it server-side.
export async function listProducts(env, firebaseToken) {
  if (productsCache && productsCache.expiresAt > Date.now()) {
    return productsCache.products;
  }

  // Fire the first PARALLEL_PAGE_BURST pages all at once instead of one
  // at a time - Promise.all resolves in the same order its input array
  // was given, regardless of which request actually finished first, so
  // burstResults[i] is always page i and concatenating them in order is
  // safe. Stop at the first page that comes back done/empty - a normal
  // offset-based backend never has a later page with more rows than an
  // earlier "past the end" one, so nothing after that point is checked.
  const burstOffsets = Array.from(
    { length: PARALLEL_PAGE_BURST },
    (_, i) => i * PAGE_SIZE,
  );
  const burstResults = await Promise.all(
    burstOffsets.map((offset) =>
      callStoreApi(env, firebaseToken, {
        action: 'app_list_products',
        offset,
        limit: PAGE_SIZE,
      }),
    ),
  );

  const all = [];
  let reachedEnd = false;
  for (const data of burstResults) {
    const rows = Array.isArray(data.products) ? data.products : [];
    all.push(...rows.map(productFromRow));
    if (data.done || rows.length === 0) {
      reachedEnd = true;
      break;
    }
  }

  // Catalog grew past what the burst covers (rare, and only gets hit at
  // all once the store is past PARALLEL_PAGE_BURST * PAGE_SIZE products)
  // - keep going the old, sequential way for whatever's left. Correctness
  // never depends on the burst size being right, only speed does.
  if (!reachedEnd) {
    let offset = PARALLEL_PAGE_BURST * PAGE_SIZE;
    for (;;) {
      const data = await callStoreApi(env, firebaseToken, {
        action: 'app_list_products',
        offset,
        limit: PAGE_SIZE,
      });
      const rows = Array.isArray(data.products) ? data.products : [];
      all.push(...rows.map(productFromRow));
      if (data.done || rows.length === 0) break;
      offset += rows.length;
    }
  }

  productsCache = { products: all, expiresAt: Date.now() + PRODUCTS_CACHE_MS };
  return all;
}
