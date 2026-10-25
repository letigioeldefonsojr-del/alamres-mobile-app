// Almares 328 chat proxy (and push-notification sender).
//
// This Worker is the ONLY place the real Anthropic (Claude) API key and the
// OneSignal REST API key ever live. The Flutter app never sees either one -
// it just calls this Worker's URL, and this Worker calls Claude/OneSignal on
// the app's behalf.
//
// Why this exists at all: both of those are real secrets. An Anthropic key
// could run up charges on the store's account; a OneSignal REST API key is
// even more sensitive - anyone who has it can push a notification to EVERY
// user of the app, not just rack up a bill. Baking either one into the app
// with --dart-define (as this project used to do for OneSignal) still ships
// it inside the compiled APK in a recoverable form - anyone who downloads
// the app can pull it back out with little effort. Routing every request
// through here keeps both keys on a server you control instead of inside
// the app bundle, and also means `flutter build apk --release` no longer
// needs any --dart-define flags at all.
//
// Two things gate every request before it reaches Claude:
//   1. The caller must send a valid Firebase ID token for THIS app's
//      Firebase project - i.e. they must actually be a logged-in Almares
//      328 user. This stops randoms on the internet from finding this
//      Worker's URL and burning through the store's Anthropic quota.
//   2. ANTHROPIC_API_KEY and CLAUDE_MODEL must both be configured (see
//      SETUP_CHATBOT.md). Until they are, this Worker answers with a
//      friendly "not set up yet" message instead of erroring, so the app's
//      chat screen is fully testable before an Anthropic account exists.
//
// On top of plain Q&A, Claude can also call two read-only tools (see
// firestore.js) to look up the real, live product catalog and the signed-in
// customer's own orders - that's what lets it answer "is X in stock?" or
// "where's my order?" instead of just guessing. Those tools only turn on
// once FIREBASE_SERVICE_ACCOUNT_KEY is configured (also in
// SETUP_CHATBOT.md); without it the chatbot still works, it just says so
// instead of making up stock numbers or order statuses.

import { createRemoteJWKSet, jwtVerify } from 'jose';
import { listProducts, getOrderById, listRecentOrdersForUser } from './firestore.js';

// Firebase ID tokens are signed with Google's securetoken key set - this is
// the same public JWKS endpoint Firebase Admin SDKs use to verify them.
const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

async function verifyFirebaseToken(token, projectId) {
  const { payload } = await jwtVerify(token, FIREBASE_JWKS, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });
  return payload;
}

function jsonResponse(body, status, extraHeaders) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...extraHeaders },
  });
}

const TOOLS = [
  {
    name: 'list_products',
    description:
      "Looks up real products from the Almares 328 catalog - name, price, " +
      'wholesale price, stock/availability, flavors/variants, best-seller ' +
      "status, and active discounts. Use this for ANY question about what's " +
      'for sale, a specific product, stock availability, best sellers, or ' +
      'discounts - never guess this information, and never do discount ' +
      "math yourself. Each product/flavor's `price` is ALREADY the amount " +
      "the customer pays right now (it already has any live discount " +
      "applied) - quote that number directly as the price. `regularPrice` " +
      'only appears when a discount is currently live, as the pre-discount ' +
      'amount to mention alongside it (e.g. "now ₱20, was ₱35"). ' +
      '`wholesalePrice` is separate and never combines with a discount - ' +
      "buying 6+ pcs charges wholesalePrice INSTEAD of the discounted " +
      'price, they never stack. Returns up to 40 matches; call again with ' +
      'a narrower search or category if needed. A discounted product also ' +
      'includes discountStarts/discountEnds (ISO 8601 dates) when those ' +
      'are set - mention the end date in plain language ("through October ' +
      '20") if a customer asks how long a discount lasts, and say it ' +
      "doesn't have a set end date if discountEnds is absent rather than " +
      'guessing one.',
    input_schema: {
      type: 'object',
      properties: {
        search: {
          type: 'string',
          description:
            'Optional keyword to match against product names, e.g. "sardines" or "coffee".',
        },
        category: {
          type: 'string',
          description:
            'Optional category to filter by, e.g. "Canned Goods" or "Beverages".',
        },
        best_sellers_only: {
          type: 'boolean',
          description: 'If true, only return products currently marked as a best seller.',
        },
      },
    },
  },
  {
    name: 'get_order_status',
    description:
      "Looks up the status of the signed-in customer's own order(s) - " +
      'always scoped to this customer, never another one. Omit order_id to ' +
      'get their most recent orders.',
    input_schema: {
      type: 'object',
      properties: {
        order_id: {
          type: 'string',
          description: 'Optional specific order ID, if the customer mentioned one.',
        },
      },
    },
  },
];

// Mirrors isDiscountActive() in lib/core/product_helpers.dart - a
// discount only counts as live right now if discountPercent is positive
// AND (there's no discountStart or it's already passed) AND (there's no
// discountEnd or it hasn't passed yet). Dates come through from Firestore
// as ISO 8601 strings (see fromFirestoreValue's timestampValue case).
function isDiscountActive(p) {
  const percent = p.discountPercent;
  if (typeof percent !== 'number' || percent <= 0) return false;
  const now = Date.now();
  if (p.discountStart && now < Date.parse(p.discountStart)) return false;
  if (p.discountEnd && now > Date.parse(p.discountEnd)) return false;
  return true;
}

function parsePesoAmount(value) {
  if (typeof value !== 'string') return null;
  const digits = value.replace(/[^0-9.]/g, '');
  if (!digits) return null;
  const n = Number(digits);
  return Number.isFinite(n) ? n : null;
}

function formatPesoAmount(n) {
  return `₱${n.toFixed(2)}`;
}

// Mirrors _isLegacyDiscount() in product_helpers.dart - an older-style
// discount was applied by rewriting `price` directly and stashing the
// pre-discount amount in `originalPrice` (on the product, or on the
// specific flavor when one is given). When that's the case `price` is
// ALREADY the discounted amount, so the percentage math below must not
// run again on top of it.
function isLegacyDiscount(entity) {
  const original = entity.originalPrice;
  return typeof original === 'string' && original.trim().length > 0;
}

// Mirrors effectivePrice() in product_helpers.dart - what the customer
// actually pays RIGHT NOW for a raw `price` string, given the product's
// (or flavor's) discount state. Computed here, server-side, rather than
// left for Claude to multiply itself - a chatbot getting a price wrong is
// a much worse failure than a formatting slip.
function effectivePrice(product, regularPrice, variant) {
  const entity = variant || product;
  if (isLegacyDiscount(entity)) return regularPrice;
  if (!isDiscountActive(product)) return regularPrice;
  const parsed = parsePesoAmount(regularPrice);
  if (parsed == null) return regularPrice;
  return formatPesoAmount((parsed * (100 - product.discountPercent)) / 100);
}

function summarizeProduct(p) {
  const flavors = Array.isArray(p.flavors) && p.flavors.length > 0 ? p.flavors : null;
  const base = {
    name: p.name,
    category: p.category,
    bestSeller: p.bestSeller === true,
    onDiscount: isDiscountActive(p),
    discountPercent: p.discountPercent,
    // Omitted entirely when not set, rather than sent as null/undefined -
    // so the assistant isn't tempted to say "no end date" when the field
    // just wasn't configured vs. genuinely open-ended.
    ...(p.discountStart ? { discountStarts: p.discountStart } : {}),
    ...(p.discountEnd ? { discountEnds: p.discountEnd } : {}),
  };
  // price is always what the customer pays RIGHT NOW (already reflects any
  // live discount). regularPrice only appears when that differs from the
  // pre-discount price, to mention as the crossed-out "was" price - never
  // present for a product that isn't currently discounted. wholesalePrice
  // is separate and unaffected by a discount - per effectivePriceForQuantity()
  // in product_helpers.dart, buying 6+ pcs charges wholesalePrice INSTEAD of
  // a discount, the two never stack.
  if (flavors) {
    base.flavors = flavors.map((f) => {
      const effective = effectivePrice(p, f.price, f);
      const flavorOut = {
        name: f.name,
        price: effective,
        wholesalePrice: f.wholesalePrice,
        stock: f.stock,
        inStock: f.available !== false && Number(f.stock || 0) > 0,
      };
      if (effective !== f.price) flavorOut.regularPrice = f.price;
      return flavorOut;
    });
  } else {
    const effective = effectivePrice(p, p.price, null);
    base.price = effective;
    if (effective !== p.price) base.regularPrice = p.price;
    base.wholesalePrice = p.wholesalePrice;
    base.stock = p.stockCount;
    base.inStock = p.available !== false && Number(p.stockCount || 0) > 0;
  }
  return base;
}

// Mirrors the same rule the Flutter app's order details screen uses once
// an order is actually out for delivery: the original "3 days from when
// you ordered" timestamp stops being the useful number, and what matters
// is just whether it's coming today or tomorrow. 8 PM Philippine time is
// the cutoff - marked on_the_way before 8 PM, it's still arriving today;
// after that, it's realistically a tomorrow delivery. The Worker runs on
// UTC, so this converts to PHT (UTC+8, no DST) explicitly rather than
// relying on the runtime's own clock/timezone.
// Sends one push notification via OneSignal's REST API, targeting a
// customer by the Firebase uid they were logged in with when OneSignal
// registered them (OneSignal.login(uid) on the Flutter side). The real
// request to OneSignal happens here, server-side, using the
// ONESIGNAL_REST_API_KEY secret - never inside the app.
//
// NOTE on trust: this only requires the caller to be SOME logged-in
// Almares 328 user (same bar as the chat endpoint), not specifically the
// target user or an admin - there's no admin-role check here because the
// companion admin website isn't part of this codebase, so this Worker has
// no way to verify an "admin" claim it doesn't know the shape of. If admin
// actions (e.g. marking an order "on the way") ever call this endpoint
// directly, it's worth tightening this later - e.g. checking a custom
// claim on the Firebase token, or moving the trigger into a Firestore
// Cloud Function instead of calling this Worker from the browser.
async function handleSendPush(request, env, corsHeaders) {
  const hasAppId =
    typeof env.ONESIGNAL_APP_ID === 'string' && env.ONESIGNAL_APP_ID.length > 0;
  const hasRestKey =
    typeof env.ONESIGNAL_REST_API_KEY === 'string' && env.ONESIGNAL_REST_API_KEY.length > 0;

  if (!hasAppId || !hasRestKey) {
    // Not configured yet - fail quietly rather than erroring, same spirit
    // as the chat endpoint's "not set up yet" response, so the rest of the
    // app (order placing, status updates, etc.) keeps working fine even
    // before OneSignal's backend secret is set.
    return jsonResponse(
      { ok: false, error: 'Push notifications are not configured on the backend yet.' },
      200,
      corsHeaders,
    );
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ ok: false, error: 'Invalid JSON body.' }, 400, corsHeaders);
  }

  const toFirebaseUid = typeof body?.toFirebaseUid === 'string' ? body.toFirebaseUid.trim() : '';
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  const orderId = typeof body?.orderId === 'string' ? body.orderId : '';

  if (!toFirebaseUid || !message) {
    return jsonResponse(
      { ok: false, error: 'toFirebaseUid and message are required.' },
      400,
      corsHeaders,
    );
  }

  try {
    const oneSignalRes = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': `Basic ${env.ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify({
        app_id: env.ONESIGNAL_APP_ID,
        include_aliases: { external_id: [toFirebaseUid] },
        target_channel: 'push',
        headings: { en: 'Almares 328' },
        contents: { en: message },
        data: { orderId },
      }),
    });

    if (!oneSignalRes.ok) {
      const errText = await oneSignalRes.text();
      console.error(`OneSignal push failed (${oneSignalRes.status}):`, errText);
      return jsonResponse({ ok: false, error: 'Push notification failed to send.' }, 502, corsHeaders);
    }

    return jsonResponse({ ok: true }, 200, corsHeaders);
  } catch (err) {
    console.error('Push send error:', err);
    return jsonResponse(
      { ok: false, error: 'Something went wrong sending the push notification.' },
      500,
      corsHeaders,
    );
  }
}

function isBeforeDeliveryCutoffPHT(now = new Date()) {
  const phtHour = (now.getUTCHours() + 8) % 24;
  return phtHour < 20;
}

function summarizeOrder(o) {
  // Once the order is on_the_way, report "Today"/"Tomorrow" instead of the
  // original stored estimate - otherwise the chatbot keeps citing a stale
  // date (e.g. "October 13") even while the customer's own app screen has
  // already moved on to showing "Today".
  const estimatedDelivery =
    o.status === 'on_the_way'
      ? isBeforeDeliveryCutoffPHT()
        ? 'Today'
        : 'Tomorrow'
      : o.estimatedDelivery;

  return {
    id: o.id,
    status: o.status,
    itemCount: o.itemCount,
    items: Array.isArray(o.items)
      ? o.items.map((it) => ({
          productName: it.productName,
          flavor: it.flavor,
          amount: it.amount,
        }))
      : undefined,
    itemsSubtotal: o.itemsSubtotal,
    deliveryFee: o.deliveryFee,
    total: o.total,
    estimatedDelivery,
    createdAt: o.createdAt,
  };
}

async function runTool(name, input, env, uid) {
  try {
    if (name === 'list_products') {
      const products = await listProducts(env);
      const search = String(input?.search || '').trim().toLowerCase();
      const category = String(input?.category || '').trim().toLowerCase();
      const bestOnly = input?.best_sellers_only === true;

      const filtered = products.filter((p) => {
        if (search && !String(p.name || '').toLowerCase().includes(search)) return false;
        if (category && String(p.category || '').toLowerCase() !== category) return false;
        if (bestOnly && p.bestSeller !== true) return false;
        return true;
      });

      return {
        matchCount: filtered.length,
        products: filtered.slice(0, 40).map(summarizeProduct),
      };
    }

    if (name === 'get_order_status') {
      if (input?.order_id) {
        const order = await getOrderById(env, String(input.order_id), uid);
        if (!order) {
          return { error: 'No order with that ID was found for this customer.' };
        }
        return { order: summarizeOrder(order) };
      }
      const orders = await listRecentOrdersForUser(env, uid, 5);
      return { orders: orders.map(summarizeOrder) };
    }

    return { error: `Unknown tool: ${name}` };
  } catch (err) {
    console.error(`Tool "${name}" failed:`, err);
    return { error: 'Could not reach the store database right now. Please try again shortly.' };
  }
}

function buildSystemPrompt(hasFirestore) {
  const base =
    'You are the customer support assistant for Almares 328, a wholesale ' +
    'grocery and sari-sari store in the Philippines. Be friendly, concise, ' +
    'and helpful.\n\n' +
    'How ordering works, if a customer asks: browse products by category or ' +
    'search, open a product to pick a flavor/variant and quantity, then add ' +
    'it to the cart or buy it directly. Buying 6 or more pieces of the same ' +
    "product/flavor in one go automatically charges that item's wholesale " +
    'price instead of the regular price. At checkout the customer picks a ' +
    'delivery address and a delivery fee is calculated from the distance to ' +
    'the nearest branch, then they confirm the order. Orders start as ' +
    '"Pending" and move through Approved, On the Way, and Delivered (or, ' +
    'rarely, Rejected / Cancelled / Unable to Deliver) - customers can check ' +
    'status anytime under Profile > My Orders.';

  const toolGuidance = hasFirestore
    ? '\n\nYou have tools to look up the real, current product catalog ' +
      "(prices, stock, best sellers, discounts) and this customer's own " +
      'orders. Always call a tool instead of guessing when asked about a ' +
      'specific product, stock, or an order - never invent a price, stock ' +
      'count, or order status. If a tool returns no results or an error, ' +
      'say so plainly instead of making something up.'
    : "\n\nYou do not currently have live access to this store's product " +
      'catalog, stock levels, or order data, so say so if asked for any of ' +
      'that instead of guessing.';

  const formattingGuidance =
    '\n\nYour replies are shown in a simple chat bubble that renders basic ' +
    'Markdown - you may use **bold** (e.g. for product names or prices) ' +
    'and "-" for list items, both will display properly. Do not use ' +
    '# headers, Markdown tables, or code blocks - they will look out of ' +
    'place in a chat bubble. Keep replies short and conversational rather ' +
    'than heavily formatted.';

  return base + toolGuidance + formattingGuidance;
}

export default {
  async fetch(request, env) {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return jsonResponse({ ok: false, error: 'Method not allowed' }, 405, corsHeaders);
    }

    // --- 1. Must be a logged-in Almares 328 user. ---
    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token) {
      return jsonResponse(
        { ok: false, error: 'Missing Authorization token.' },
        401,
        corsHeaders,
      );
    }

    let uid;
    try {
      const payload = await verifyFirebaseToken(token, env.FIREBASE_PROJECT_ID);
      uid = payload.sub;
    } catch (err) {
      return jsonResponse(
        { ok: false, error: 'Your session has expired. Please log in again.' },
        401,
        corsHeaders,
      );
    }

    // --- 1b. Push notifications are a separate job from chat - route by
    // path. Everything below this point (steps 2+) is chat-only. ---
    const url = new URL(request.url);
    if (url.pathname === '/send-push') {
      return handleSendPush(request, env, corsHeaders);
    }

    // --- 2. Not configured yet? Answer nicely instead of failing. ---
    const hasKey = typeof env.ANTHROPIC_API_KEY === 'string' && env.ANTHROPIC_API_KEY.length > 0;
    const hasModel =
      typeof env.CLAUDE_MODEL === 'string' &&
      env.CLAUDE_MODEL.length > 0 &&
      env.CLAUDE_MODEL !== 'REPLACE_WITH_MODEL_ID';

    if (!hasKey || !hasModel) {
      return jsonResponse(
        {
          ok: true,
          reply:
            "I'm not connected to an AI model yet - the store still needs " +
            'to add a Claude API key and pick a model on the backend.',
        },
        200,
        corsHeaders,
      );
    }

    const hasFirestore =
      typeof env.FIREBASE_SERVICE_ACCOUNT_KEY === 'string' &&
      env.FIREBASE_SERVICE_ACCOUNT_KEY.trim().length > 0;

    // --- 3. Parse the conversation sent by the app. ---
    let body;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ ok: false, error: 'Invalid JSON body.' }, 400, corsHeaders);
    }

    const incomingMessages = Array.isArray(body?.messages) ? body.messages : null;
    if (!incomingMessages || incomingMessages.length === 0) {
      return jsonResponse({ ok: false, error: 'messages[] is required.' }, 400, corsHeaders);
    }

    // --- 4. Call Claude, letting it call tools (if configured) before it
    // gives its final answer. ---
    const system = buildSystemPrompt(hasFirestore);
    const messages = [...incomingMessages];
    const MAX_TOOL_ROUNDS = 4;
    // Tallied across every round below (a single customer message can mean
    // more than one Claude call, when a tool gets used) and logged at the
    // end - watch it live with `npx wrangler tail` while testing.
    let totalInputTokens = 0;
    let totalOutputTokens = 0;

    try {
      for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
        const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-api-key': env.ANTHROPIC_API_KEY,
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify({
            model: env.CLAUDE_MODEL,
            max_tokens: 1500,
            system,
            messages,
            ...(hasFirestore ? { tools: TOOLS } : {}),
          }),
        });

        const data = await anthropicRes.json();

        if (!anthropicRes.ok) {
          console.error('Anthropic API error:', data);
          return jsonResponse(
            { ok: false, error: 'The assistant is temporarily unavailable. Please try again later.' },
            502,
            corsHeaders,
          );
        }

        if (data.usage) {
          totalInputTokens += data.usage.input_tokens || 0;
          totalOutputTokens += data.usage.output_tokens || 0;
          console.log(
            `[tokens] round ${round}: ${data.usage.input_tokens} in / ` +
              `${data.usage.output_tokens} out (running total: ` +
              `${totalInputTokens} in / ${totalOutputTokens} out)`,
          );
        }

        const toolUses = (data.content || []).filter((b) => b.type === 'tool_use');

        if (data.stop_reason === 'tool_use' && toolUses.length > 0 && round < MAX_TOOL_ROUNDS) {
          const toolResults = [];
          for (const toolUse of toolUses) {
            const result = await runTool(toolUse.name, toolUse.input, env, uid);
            toolResults.push({
              type: 'tool_result',
              tool_use_id: toolUse.id,
              content: JSON.stringify(result),
            });
          }
          messages.push({ role: 'assistant', content: data.content });
          messages.push({ role: 'user', content: toolResults });
          continue;
        }

        const reply =
          (data.content || [])
            .filter((b) => b.type === 'text')
            .map((b) => b.text)
            .join('\n')
            .trim() || "Sorry, I didn't catch that - could you rephrase?";
        console.log(
          `[tokens] this message's total: ${totalInputTokens} in / ` +
            `${totalOutputTokens} out (${round + 1} Claude call${round === 0 ? '' : 's'})`,
        );
        return jsonResponse({ ok: true, reply }, 200, corsHeaders);
      }

      // Hit MAX_TOOL_ROUNDS without a final answer - shouldn't normally
      // happen, but fail gracefully instead of hanging.
      return jsonResponse(
        { ok: true, reply: "Sorry, that's taking a bit too long to look up - could you try asking again?" },
        200,
        corsHeaders,
      );
    } catch (err) {
      console.error('Worker error:', err);
      return jsonResponse(
        { ok: false, error: 'Something went wrong talking to the assistant.' },
        500,
        corsHeaders,
      );
    }
  },
};
