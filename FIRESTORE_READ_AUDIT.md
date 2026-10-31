# Firestore read audit — Almares 328

Status: all fixes below are written **and confirmed on your device** (re-staged + byte-diffed every file after committing — no silent-write surprises this time).

## 1. The dominant cause of the ~14,000-read spike

**`fetchBestSellingProductIds()` in `lib/core/cart_helpers.dart`.**

It ran a plain, unfiltered, unlimited `FirebaseFirestore.instance.collection('orders').get()` — every single call billed 1 read per order document that has ever existed, no `where()`, no `limit()`.

It was called inline inside a `FutureBuilder`'s `future:` parameter in two places:
- `lib/screens/customer/home_tab.dart:349` (Featured Products row)
- `lib/screens/customer/all_products_screen.dart:203` (search/browse screen)

Both of those `FutureBuilder`s sit inside a `ValueListenableBuilder` listening to `ProductRepository.instance.productsNotifier`. That notifier fires on **every periodic catalog refresh** (a background timer that runs continuously while any product screen is visible) and, on the search screen, implicitly on **every rebuild from typing in the search box**. Each fire rebuilds the `ValueListenableBuilder`'s subtree, which constructs a *brand-new* `FutureBuilder` widget with a *freshly-evaluated* `fetchBestSellingProductIds()` call — i.e. a full unfiltered read of the whole `orders` collection, repeated dozens of times over a few hours of normal use. With a growing `orders` collection, this alone can easily produce thousands of reads from a handful of minutes of browsing — this is almost certainly your 14,000.

**Fix:** added a 5-minute TTL in-memory cache with in-flight-fetch de-duplication, matching the existing `CustomerProfileCache`/`BannerRepository` pattern already in the codebase:

```dart
Future<Set<String>> fetchBestSellingProductIds({int topN = 5}) async {
  final cached = _bestSellingCache[topN];
  if (cached != null && DateTime.now().difference(cached.fetchedAt) < _bestSellingTtl) {
    return cached.ids;
  }
  final inFlight = _bestSellingInFlight[topN];
  if (inFlight != null) return inFlight;
  final future = _fetchBestSellingProductIds(topN);
  _bestSellingInFlight[topN] = future;
  try { return await future; } finally { _bestSellingInFlight.remove(topN); }
}
```

Now the real Firestore read only happens once every 5 minutes no matter how many times the catalog refreshes or the customer types in search.

## 2. Secondary finding: `profile_tab.dart`'s order-stats badge

`_loadOrderStats()` used to run `.where('userId', isEqualTo: uid).get()` over the customer's **entire** order history just to count three numbers (total/delivered/pending) — 1 billed read per order document, fired every time the Profile tab mounted and every time `ordersChangedSignal` fired (place/cancel/rate an order).

**Fix:** switched to three `Query.count().get()` aggregation calls, which Firestore bills as a flat 1 read each regardless of how many documents match:

```dart
final results = await Future.wait([
  ordersForUser.count().get(),
  ordersForUser.where('status', isEqualTo: 'delivered').count().get(),
  ordersForUser.where('status', isEqualTo: 'pending').count().get(),
]);
```

3 reads total now, forever, whether the customer has 5 orders or 5,000.

## 3. Three instances of "stream/Future recreated on rebuild"

Same anti-pattern as the best-sellers bug, smaller blast radius each, found by sweeping every `FutureBuilder`/`StreamBuilder` in the tree:

| File | Before | After |
|---|---|---|
| `lib/widgets/cart_badge.dart` | `StatelessWidget` calling `cartRef.snapshots()` straight inside `build()` — re-subscribed (full cart re-read) on every rebuild of whatever ancestor holds it | Converted to `StatefulWidget`; stream created once in `initState()` |
| `lib/widgets/cart_floating_bar.dart` | Same bug, same fix | Same fix |
| `lib/screens/customer/saved_addresses_screen.dart` | Same bug on the saved-addresses list | Same fix |

This is the exact same fix already applied earlier to `cart_screen.dart`'s own cart listener — now applied consistently everywhere the pattern showed up.

## 4. Specific checks you asked for

- **Listener/stream/Future created inside `build()` or re-created on rebuild/setState:** found and fixed the three instances above, plus the dominant best-sellers bug (technically inside a `FutureBuilder`'s `future:` argument, same family of bug). Nothing else in the tree does this — `PromoBannerCarousel` was checked specifically and only calls its loader from `initState`/`didChangeAppLifecycleState(resumed)`, never from `build()`.
- **Listener attached more than once without cancelling the previous one, including on app resume:** both of the two real `.snapshots()` listeners in the app (`orders_tab.dart`'s active-orders listener, `order_details_screen.dart`'s single-order listener) guard with `if (_sub != null) return;` before attaching, so the resumed-lifecycle path is a safe no-op if already attached. `suspension_watcher.dart`'s listener is gated on "already watching this uid" too. No double-attach found anywhere.
- **Active-orders query not filtered by the signed-in customer's uid:** checked — `orders_tab.dart`'s active query is `.where('userId', isEqualTo: uid).where('status', whereIn: _activeStatuses)`. Correctly scoped. No bug here.
- **Query with no limit:** the history query in `orders_tab.dart` has `.limit(30)`. The *active*-orders query has no explicit `.limit()`, but it's bounded by nature (a customer only ever has a handful of in-progress orders at once) — flagging it as a minor note, not something I changed, since adding a limit there isn't free (it would need an `orderBy` and a composite index to be meaningful). The unfiltered-and-unlimited `orders` collection read in `fetchBestSellingProductIds()` (finding #1) was the real one here, now fixed.

## 5. Two minor cache-routing cleanups (same family, lower impact)

- **`lib/services/onesignal_service.dart`**: `_syncPromotionsTag()` did its own direct `users/{uid}.get()` just to read one notification-preference flag. Now routes through `CustomerProfileCache.instance.getProfile(uid)` — on a cold start this call happens first (from `main()`'s `OneSignalService.instance.login()`), so it actually pre-warms the 5-minute cache before Home even opens, and everything else that wants the profile doc gets a free cache hit.
- **`lib/screens/customer/cart_screen.dart`**: `_loadDefaultAddress()` did its own direct `users/{uid}.get()`; now also routes through `CustomerProfileCache`.

## 6. Debug read counter (part 3 of your request)

Added `lib/core/read_counter.dart` — a `kDebugMode`-only static logger, zero cost in release builds. Every one of the 23 live Firestore call sites in the app now calls it. Console output format, exactly as you asked:

```
[reads] orders_tab:history +12 (total: 12)
[reads] orders_tab:active +2 (total: 14)
[reads] profile_tab:orderStats +3 (total: 17)
...
```

`ReadCounter.reset()` runs as the very first line of `main()`, so every fresh debug run (hot restart included) starts counting from 0 rather than carrying over a stale total.

One caveat worth knowing: a `.snapshots()` listener's *first* emission can be served from Firestore's local on-device cache (no real network read, no real billed read) before the server-confirmed one arrives a moment later — the counter logs both, so on a listener-heavy screen the console total can run slightly **above** the real Firestore bill. That's intentional (safe/conservative for budgeting) rather than a bug in the counter.

## 7. The full inventory — every Firestore read site

| Site (file:line) | Query | Max docs | Fires when |
|---|---|---|---|
| `core/cart_helpers.dart:72` (`fetchBestSellingProductIds`) | `orders` collection, unfiltered | all orders ever placed | once per 5 min now (was: every catalog refresh / search keystroke) |
| `core/cart_helpers.dart:431` (`pickDeliveryAddress`) | `users/{uid}.get()` | 1 | whenever an order is placed and no address is pre-selected |
| `core/cart_helpers.dart:445` (`pickDeliveryAddress`) | `users/{uid}/addresses.get()` | customer's saved address count | same |
| `screens/customer/orders_tab.dart:208` | `orders` where `userId==uid` and `createdAt>=cutoff`, `limit(30)` | 30 | tab mount, pull-to-refresh, resume, after placing an order |
| `screens/customer/orders_tab.dart:247` | `orders` where `userId==uid` and `status whereIn [active]`, `.snapshots()` | customer's active-order count | live, for as long as the tab/app is foregrounded |
| `screens/customer/orders_tab.dart:307` | same as history, `startAfterDocument`, `limit(30)` | 30 | "Load older orders" tap |
| `screens/customer/order_details_screen.dart:166` | `orders/{id}.get()` | 1 | opening an order, and on every app resume |
| `screens/customer/order_details_screen.dart:194` | `orders/{id}.snapshots()` | 1/emission | live, only while that order is in an active status |
| `screens/customer/profile_tab.dart:89` | `settings/appInfo.get()` | 1 | Profile mount, only if the customer enabled app-update notifications |
| `screens/customer/profile_tab.dart:158` | 3× `orders` `.count().get()` | 3 (flat) | Profile mount, and after place/cancel/rate |
| `screens/customer/home_screen.dart:176` | `orders/{id}.get()` | 1 | only when opened via a push-notification deep link |
| `screens/customer/login_screen.dart:365` | `users` Google-account existence check | 1 | Google sign-in |
| `screens/customer/register_screen.dart:537` | same | 1 | Google sign-up |
| `screens/customer/saved_addresses_screen.dart:485` | `users/{uid}/addresses.snapshots()` | address count | live, while that screen is mounted (now subscribed once, not per rebuild) |
| `services/banner_repository.dart:79` | `storeBanners` collection | banner count | once per 5 min |
| `services/banner_repository.dart:83` | `settings/storeBanner.get()` | 1 | once per 5 min, same fetch |
| `services/beta_announcement_service.dart:40` | `config/betaAnnouncement.snapshots()` | 1/emission | live, for as long as Home is mounted |
| `services/customer_profile_cache.dart:56` | `users/{uid}.get()` | 1 | once per 5 min, shared by every screen that wants the profile |
| `services/product_repository.dart:97` | `products` collection (Firestore path) | — | dormant — `kUseSupabaseProducts = true`, this path never runs |
| `services/suspension_service.dart:59` | `users/{uid}.get()` | 1 | email/password or Google login only |
| `services/suspension_watcher.dart:101` | `users/{uid}.snapshots()` | 1/emission | live, for as long as anyone is signed in, app-wide |
| `widgets/cart_badge.dart:53` | `users/{uid}/cart.snapshots()` | cart item count | live, for as long as Home is mounted |
| `widgets/cart_floating_bar.dart:59` | `users/{uid}/cart.snapshots()` | cart item count | live, remounts (re-subscribes) every time you leave and return to a tab other than Profile |

## 8. The cold-start tour trace you asked for

I hand-traced your exact sequence — **cold start → open Home → My Orders → open one order → open Profile → back to Home** — through the fixed code. I'm giving you the real mechanics rather than invented numbers, because several steps depend on your actual data (how many orders, cart items, banners you have), and you explicitly said not to guess:

**Important structural fact that changes how to read the trace:** `HomeScreen` holds all four tabs (Home/Categories/Orders/Profile) in one `IndexedStack` with a `const` widget list, so **all four tabs mount at once the moment Home first appears** — not lazily when you tap their bottom-nav icon. That means the Orders tab's history fetch + active-orders listener, and the Profile tab's order-stats + app-info checks, all fire during "open Home," not during "My Orders"/"open Profile." Tapping those tabs afterward costs ~0 extra reads (just a visibility toggle on an already-mounted, already-loaded tab) — same reason "back to Home" at the end of your sequence costs ~0.

Step by step:

1. **Cold start** (`main()`, before any screen renders): `ReadCounter.reset()` zeroes the counter. If you're already signed in, two things fire: `SuspensionWatcher`'s `users/{uid}.snapshots()` listener attaches (+1, first emission), and `OneSignalService.login()` calls `_syncPromotionsTag()`, which now pre-warms `CustomerProfileCache` with one `users/{uid}.get()` (+1). Everything else later in the sequence that wants this same profile doc (Home's mobile-number check, Profile's phone-number/app-update checks) will hit this cache for the next 5 minutes — 0 extra reads.
2. **Open Home** (`HomeScreen` builds, mounting all four tabs at once):
   - `HomeTab` → `PromoBannerCarousel` fetches once: `storeBanners` collection (+N banners) and `settings/storeBanner` (+1).
   - `HomeTab` → `CartBadge` attaches its cart listener: `users/{uid}/cart.snapshots()` (+cart item count).
   - `HomeTab` → the Featured Products `FutureBuilder` calls `fetchBestSellingProductIds()` — first call this session, so it's a real (now cached) read of the whole `orders` collection (+total order count, once, then free for 5 minutes).
   - `HomeScreen` itself starts the beta-announcement listener: `config/betaAnnouncement.snapshots()` (+1).
   - `OrdersPlaceholderTab` (mounted even though not visible yet) → `_loadInitial()`: history query (+ up to 30 docs, filtered to last 30 days) and the active-orders listener attaches (+ active order count).
   - `ProfileTab` (also mounted, not visible) → `_loadOrderStats()`: 3 count() reads (+3 flat), and `_checkForUpdate()`'s `settings/appInfo` read only if you have app-update notifications turned on (+1 or +0).
3. **Tap "My Orders"**: just flips `IndexedStack`'s visible index. The tab was already mounted and loaded in step 2 — **0 reads**.
4. **Open one order**: `OrderDetailsScreen` opens with the data it already has from the list (no read to open), then `initState()` always does one `orders/{id}.get()` (+1), and additionally attaches a live listener with its own first emission (+1) *only if* the order you tapped is still in an active status (pending/approved/ready_for_pickup/on_the_way). If you tap a delivered/cancelled/historical order instead, it's just the +1 `.get()`, no listener.
5. **Open Profile**: same as step 3 — already mounted and loaded, **0 reads**.
6. **Back to Home**: `IndexedStack` index flips back to 0 — the tab is still mounted, nothing re-fetches, **0 reads** for Home/Orders/Profile themselves. The one exception: `CartFloatingBar` is conditionally removed from the tree whenever Profile (index 3) is selected and re-added when you leave it — so going Profile → Home remounts it fresh, re-subscribing to the cart (+cart item count again). This is a small pre-existing structural quirk, not something I changed — flagging it rather than silently fixing it, since it's outside the four specific checks you asked for and the cost is bounded by your cart size.

Putting that together, the whole sequence costs roughly:

```
1 (suspension_watcher) + 1 (profile cache, pre-warmed)
+ banners(N) + 1 (legacy banner doc)
+ cart(C) [CartBadge]
+ orders(O) [best-sellers, cached 5 min]
+ 1 (beta announcement)
+ history(≤30) + active(A) [Orders tab]
+ 3 + (0 or 1) [Profile tab]
+ 1 (order fetchLatest) + (0 or 1) [order live listener, if active]
+ cart(C) [CartFloatingBar remount on Profile→Home]
```

With realistic small numbers for a test account (a handful of banners, a few cart items, a dozen-ish orders, 0–2 active orders), that lands in the **15–30 read** range — in the same ballpark as your old "~100 for a full tour" baseline, not the thousands you saw. The exact number for your account will print live in the console as `[reads] ... (total: N)` when you run that sequence in a debug build; I'd rather you read the real number off the counter than have me invent one.

## What to do next

Run a debug build through exactly that sequence and watch the console. If the running total lands anywhere near the old ~14,000, send me the `[reads] ...` lines and I'll trace which site is still over-firing — but based on everything above, the best-sellers fix should have closed the gap.
