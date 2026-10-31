# Follow-up: orders collection fully removed from best-sellers, full inventory

## Fix

`fetchBestSellingProductIds()` in `lib/core/cart_helpers.dart` no longer touches Firestore at all. It now calls the Supabase `store-api` Edge Function — the same one `app_get_products` already uses — via a new method:

```dart
// lib/services/supabase_products.dart
Future<List<String>> bestSellingProductIds({int limit = 20}) async {
  final data = await _call({'action': 'app_best_sellers', 'limit': limit});
  return ((data['ids'] as List?) ?? const [])
      .map((id) => id.toString())
      .toList();
}
```

```dart
// lib/core/cart_helpers.dart
Future<Set<String>> _fetchBestSellingProductIds(int topN) async {
  try {
    final ids = await SupabaseProductsApi.instance.bestSellingProductIds(limit: topN);
    final result = ids.toSet();
    _bestSellingCache[topN] = _BestSellingEntry(result, DateTime.now());
    return result;
  } catch (_) {
    // No Firestore fallback, on purpose.
    return const <String>{};
  }
}
```

The 5-minute cache and in-flight de-dup are unchanged, and the public function's name/signature/return type didn't change, so the two call sites (`home_tab.dart:349`, `all_products_screen.dart:203`) needed no edits. On failure it returns an empty set — Best Sellers/badge rows just don't show anything that call, nothing more.

One thing worth flagging: this now depends on your `store-api` Edge Function actually implementing `action: "app_best_sellers"` and returning `{"ok": true, "ids": [...]}` the way `app_get_products` does. I didn't write or touch that function (it's server-side, outside this Flutter project) — if it doesn't exist yet or returns a different shape, every call will hit the `catch` and silently return an empty set, which would make Best Sellers/the "is best selling" badge stop showing anything rather than erroring loudly. Worth a quick manual check that the Edge Function side is in place.

I had to re-commit this file once — the first `device_commit_files` call reported `"written"` with no rejection, but re-staging and diffing it straight after showed the device still had the old, pre-fix code untouched. Re-applied and re-committed; the second attempt verified byte-identical on re-stage. `supabase_products.dart` landed correctly on the first try.

## Every remaining place that touches the `orders` collection

Reads:

| File:line | What | Scoped how |
|---|---|---|
| `screens/customer/orders_tab.dart:202` | History page, `.where('userId', isEqualTo: uid).where('createdAt', >=cutoff).limit(30)` | (a) customer's own orders, uid-filtered, paged |
| `screens/customer/orders_tab.dart:240` | Active-orders listener, `.where('userId', isEqualTo: uid).where('status', whereIn: activeStatuses).snapshots()` | (a) customer's own orders, uid-filtered, live |
| `screens/customer/orders_tab.dart:300` | "Load older" page, same uid/date filter + `startAfterDocument`, `.limit(30)` | (a) customer's own orders, uid-filtered, paged |
| `screens/customer/profile_tab.dart:150` | 3× `.where('userId', isEqualTo: uid)...count().get()` | (b) profile stats, uid-filtered, aggregation |
| `screens/customer/order_details_screen.dart:163` | `orders/{orderId}.get()` | Single document by id — the one order the customer just opened, inherently returns 0 or 1 doc, can't return another customer's data |
| `screens/customer/order_details_screen.dart:189` | `orders/{orderId}.snapshots()` | Same — single document, live, only while that order is active |
| `screens/customer/home_screen.dart:173` | `orders/{orderId}.get()` | Single document by id, from a push-notification deep link (the notification itself is only ever sent to that order's own customer) |

Writes (no read cost, listed for completeness since you asked for "every remaining place that touches the orders collection"):

| File:line | What |
|---|---|
| `screens/customer/order_details_screen.dart:350` | `.update({'rating': ..., 'feedback': ..., 'ratedAt': ...})` — submitting a rating |
| `screens/customer/order_details_screen.dart:433` | `.update({'ratingPromptDismissed': true})` |
| `screens/customer/order_details_screen.dart:571` | `.update({'status': 'cancelled', 'cancelReason': ...})` — cancelling |
| `screens/customer/order_confirmation_screen.dart:243` | New order doc ref, written inside a transaction when placing a single-product order |
| `screens/customer/cart_order_confirmation_screen.dart:342` | New order doc ref, written inside a transaction when placing a cart checkout |

**Confirmed:** every read of the `orders` collection is now either (a) the signed-in customer's own orders, filtered by their `uid` (history, paged; active, live) or (b) the profile `count()` aggregation, also `uid`-filtered. The only other reads are three single-document-by-id lookups — these can't leak another customer's data by construction (a doc-id `.get()`/`.snapshots()` returns at most the one document asked for), though I'd note the actual enforcement that a customer can only ever be handed their *own* order id lives in your Firestore security rules / server-side notification logic, not in this client code — I didn't find a `firestore.rules` file in this project to check that side, so if you want that formally verified it'd need a look at wherever those rules are deployed from.

The `fetchBestSellingProductIds()` full-collection scan is gone — not throttled, gone.
