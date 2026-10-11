// Firestore REST API access for the chatbot's tools (product lookups,
// order status) - using a Firebase service account rather than the
// customer's own Firebase ID token.
//
// Why a service account: the Flutter app's Firestore security rules are
// written around what the app itself needs (a signed-in user reading or
// writing their own docs). They were never written with "an AI assistant
// looking things up on a customer's behalf" in mind, and loosening them
// just for that would open the whole database back up to anyone who could
// forge a request. A service account sidesteps rules entirely instead, so
// this file is the ONLY place that happens, and every function below is
// deliberately narrow about what it will hand back:
//   - every exported function here only ever reads, never writes (there's
//     no read-only OAuth scope for Firestore - "datastore" is the scope
//     for both reading and writing - so the no-writing guarantee comes
//     from this file simply never calling a write endpoint, not from the
//     token itself), and
//   - getOrderById always checks the order's userId against the caller's
//     own verified uid (from their Firebase ID token, checked earlier in
//     index.js) before returning anything, so one customer can never see
//     another customer's order just by guessing/asking for its ID.

import { SignJWT, importPKCS8 } from 'jose';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/datastore';

// A Google OAuth access token is valid for an hour - cache it across
// requests handled by this same Worker isolate instead of minting a new
// one on every chat message.
let cachedToken = null; // { accessToken, expiresAt }

async function getAccessToken(env) {
  if (cachedToken && cachedToken.expiresAt - Date.now() > 60_000) {
    return cachedToken.accessToken;
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_KEY);
  } catch {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_KEY is not valid JSON - it should be the ' +
        'full contents of the service account key file, unchanged.',
    );
  }

  const privateKey = await importPKCS8(serviceAccount.private_key, 'RS256');

  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: SCOPE })
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience(TOKEN_URL)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });

  if (!res.ok) {
    throw new Error(`Could not get a Firestore access token: ${await res.text()}`);
  }

  const data = await res.json();
  cachedToken = {
    accessToken: data.access_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  };
  return cachedToken.accessToken;
}

// Firestore's REST API wraps every field as {stringValue:...} /
// {integerValue:...} / etc instead of plain JSON - these unwrap that back
// into ordinary JS values/objects/arrays.
function fromFirestoreValue(value) {
  if (value == null) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) {
    return (value.arrayValue.values || []).map(fromFirestoreValue);
  }
  if ('mapValue' in value) {
    return fromFirestoreFields(value.mapValue.fields || {});
  }
  return null;
}

function fromFirestoreFields(fields) {
  const out = {};
  for (const [key, value] of Object.entries(fields)) {
    out[key] = fromFirestoreValue(value);
  }
  return out;
}

function docIdFromName(name) {
  return name.split('/').pop();
}

async function firestoreFetch(env, path, options = {}) {
  const accessToken = await getAccessToken(env);
  const base = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
  const res = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${accessToken}`,
      ...(options.headers || {}),
    },
  });
  if (!res.ok) {
    throw new Error(`Firestore request failed (${res.status}): ${await res.text()}`);
  }
  return res.json();
}

// The full product catalog, cached briefly in memory. A sari-sari store's
// catalog is small and doesn't change fast enough to justify a fresh
// Firestore read on every single tool call within one conversation - the
// customer might ask about three different products back to back.
let productsCache = null; // { products, expiresAt }
const PRODUCTS_CACHE_MS = 60_000;

export async function listProducts(env) {
  if (productsCache && productsCache.expiresAt > Date.now()) {
    return productsCache.products;
  }

  const data = await firestoreFetch(env, ':runQuery', {
    method: 'POST',
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'products' }],
        limit: 500,
      },
    }),
  });

  const products = (Array.isArray(data) ? data : [])
    .filter((entry) => entry.document)
    .map((entry) => ({
      id: docIdFromName(entry.document.name),
      ...fromFirestoreFields(entry.document.fields || {}),
    }));

  productsCache = { products, expiresAt: Date.now() + PRODUCTS_CACHE_MS };
  return products;
}

// Looks up one specific order by ID, but only ever returns it if it
// actually belongs to `uid` - the caller's own verified Firebase uid, not
// anything the model or the request body supplied.
export async function getOrderById(env, orderId, uid) {
  let data;
  try {
    data = await firestoreFetch(env, `/orders/${orderId}`);
  } catch {
    return null;
  }
  const order = { id: orderId, ...fromFirestoreFields(data.fields || {}) };
  if (order.userId !== uid) return null;
  return order;
}

// Mirrors the same userId + createdAt query the app's own "My Orders"
// screen runs (lib/screens/customer/orders_tab.dart) - that composite
// index already exists in this project because the app depends on it.
export async function listRecentOrdersForUser(env, uid, limit = 5) {
  const data = await firestoreFetch(env, ':runQuery', {
    method: 'POST',
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'orders' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'userId' },
            op: 'EQUAL',
            value: { stringValue: uid },
          },
        },
        orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
        limit,
      },
    }),
  });

  return (Array.isArray(data) ? data : [])
    .filter((entry) => entry.document)
    .map((entry) => ({
      id: docIdFromName(entry.document.name),
      ...fromFirestoreFields(entry.document.fields || {}),
    }));
}
