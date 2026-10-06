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

import { createRemoteJWKSet, jwtVerify } from 'jose';

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

    try {
      await verifyFirebaseToken(token, env.FIREBASE_PROJECT_ID);
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

    // --- 3. Parse the conversation sent by the app. ---
    let body;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ ok: false, error: 'Invalid JSON body.' }, 400, corsHeaders);
    }

    const messages = Array.isArray(body?.messages) ? body.messages : null;
    if (!messages || messages.length === 0) {
      return jsonResponse({ ok: false, error: 'messages[] is required.' }, 400, corsHeaders);
    }

    // --- 4. Call Claude. ---
    try {
      const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model: env.CLAUDE_MODEL,
          max_tokens: 1024,
          system:
            'You are the customer support assistant for Almares 328, a wholesale ' +
            'grocery and sari-sari store in the Philippines. Be friendly, concise, ' +
            "and helpful. You do not have live access to this customer's specific " +
            'orders or account data, so say so if asked for it instead of guessing.',
          messages,
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

      const reply = data?.content?.[0]?.text ?? "Sorry, I didn't catch that - could you rephrase?";
      return jsonResponse({ ok: true, reply }, 200, corsHeaders);
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
