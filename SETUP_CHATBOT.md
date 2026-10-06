# Setting up the Chat Assistant (Claude)

This adds an AI chat screen ("Chat Assistant" in the Profile tab) backed by
Anthropic's Claude. The app code is already in place and will run right
now — until you finish the steps below, it just shows a friendly
"not connected yet" message instead of a real AI reply.

## Why there's an extra "cloudflare-worker" folder

Claude's API needs a secret API key to work. That key must **never** be
inside the Flutter app itself — anyone could pull it out of the installed
app and use it to rack up charges on your account. So instead, the app
talks to a small piece of code that lives on the internet (a "Cloudflare
Worker"), and only *that* code holds the real key. The app just asks the
Worker a question; the Worker asks Claude and relays the answer back.

Cloudflare Workers were picked because they have a genuinely free tier (no
credit card required), unlike Firebase Cloud Functions, which would need
your Firebase project upgraded to a paid plan just to deploy anything.

## What you'll need

- A computer with [Node.js](https://nodejs.org) installed (any recent
  version — if you can run `node --version` in a terminal and see a number,
  you have it; if not, download the "LTS" installer from that site and
  run it).
- A free Cloudflare account: [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up)
- An Anthropic account with billing set up (so you can create an API key):
  [console.anthropic.com](https://console.anthropic.com)

## Step 1 — Install the Worker's dependencies

Open a terminal, then:

```
cd cloudflare-worker
npm install
```

This downloads `wrangler` (Cloudflare's command-line tool) and `jose` (used
to verify that whoever calls the Worker is actually a logged-in Almares
328 user).

## Step 2 — Log in to Cloudflare from the terminal

Still inside the `cloudflare-worker` folder:

```
npx wrangler login
```

This opens your browser and asks you to approve access. Once it says
you're logged in, you can close that browser tab.

## Step 3 — Get a Claude API key

1. Go to [console.anthropic.com](https://console.anthropic.com) and sign
   in (or create an account).
2. Go to **Settings → API Keys** and create a new key.
3. Copy it somewhere safe for a moment — you'll paste it once in Step 5
   and never need to type it again.
4. Optional but recommended for a student project: in the Anthropic
   console, set a monthly spending limit so a bug (like an accidental
   infinite loop of messages) can't run up an unexpected bill.

## Step 4 — Pick a Claude model

Check [docs.claude.com/en/docs/about-claude/models](https://docs.claude.com/en/docs/about-claude/models)
for the current list of model names (they change over time, so this guide
won't hardcode one). Pick one — a smaller/cheaper model is plenty for a
support chatbot.

Open `cloudflare-worker/wrangler.toml` and replace:

```
CLAUDE_MODEL = "REPLACE_WITH_MODEL_ID"
```

with the model ID you picked, e.g.:

```
CLAUDE_MODEL = "claude-..."
```

## Step 5 — Store the API key as a secret

Still in the `cloudflare-worker` folder:

```
npx wrangler secret put ANTHROPIC_API_KEY
```

It will prompt you to paste the key from Step 3, then press Enter. This
stores it encrypted on Cloudflare's servers — it does **not** get written
into any file in this project, so it can never accidentally end up in git.

## Step 6 — Deploy the Worker

```
npx wrangler deploy
```

When it finishes, it prints a URL that looks like:

```
https://almares-328-chat-proxy.<your-subdomain>.workers.dev
```

Copy that whole URL.

## Step 7 — Point the app at it

Open `lib/core/constants.dart` and replace:

```dart
const String kChatWorkerUrl = 'REPLACE_WITH_WORKER_URL';
```

with the URL you just copied, e.g.:

```dart
const String kChatWorkerUrl = 'https://almares-328-chat-proxy.your-subdomain.workers.dev';
```

Save the file. Since this is just a Dart constant change (no new
packages), a **hot restart** of the app is enough — you don't need a full
rebuild.

## Step 8 — Try it

Open the app, go to **Profile → Chat Assistant**, and send a message. If
everything above is done, you'll get a real Claude reply. If anything's
still missing (model not set, key not set), you'll see the friendly
"not connected yet" message instead of a crash — so you can tell at a
glance what's left.

## If you ever want to change the model or rotate the key later

- New model: edit `CLAUDE_MODEL` in `wrangler.toml`, then run
  `npx wrangler deploy` again.
- New/rotated key: run `npx wrangler secret put ANTHROPIC_API_KEY` again
  with the new value, then `npx wrangler deploy`.

No app changes or app rebuild are ever needed for either of those — they
only touch the Worker.
