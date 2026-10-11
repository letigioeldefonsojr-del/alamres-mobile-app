// Almares 328 chat proxy.
//
// This Worker is the ONLY place the real Anthropic (Claude) API key ever
// lives. The Flutter app never sees it - it just calls this Worker's URL,
// and this Worker calls Claude on the app's behalf.
//
// Why this exists at all: an Anthropic API key is a real secret. Anyone who
// extracted it from the app (easy to do by decompiling an APK) could run up
// charges on the store's account. Routing every request through here keeps
// the key on a server you control instead of inside the app bundle.
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
      'discounts - never guess this information. Returns up to 40 matches; ' +
      'call again with a narrower search or category if needed.',
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

function summarizeProduct(p) {
  const flavors = Array.isArray(p.flavors) && p.flavors.length > 0 ? p.flavors : null;
  const base = {
    name: p.name,
    category: p.category,
    bestSeller: p.bestSeller === true,
    onDiscount: typeof p.discountPercent === 'number' && p.discountPercent > 0,
    discountPercent: p.discountPercent,
  };
  if (flavors) {
    base.flavors = flavors.map((f) => ({
      name: f.name,
      price: f.price,
      wholesalePrice: f.wholesalePrice,
      stock: f.stock,
      inStock: f.available !== false && Number(f.stock || 0) > 0,
    }));
  } else {
    base.price = p.price;
    base.wholesalePrice = p.wholesalePrice;
    base.stock = p.stockCount;
    base.inStock = p.available !== false && Number(p.stockCount || 0) > 0;
  }
  return base;
}

function summarizeOrder(o) {
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
    estimatedDelivery: o.estimatedDelivery,
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
