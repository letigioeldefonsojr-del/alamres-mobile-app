# Almares 328 — Data Inventory (Firestore + Supabase)

Read-only investigation. No code was changed to produce this report.

---

## 1. FIRESTORE COLLECTIONS

### `users/{uid}`
- Read/write: both.
- Doc id: the Firebase Auth `uid`.
- Written by:
  - `register_screen.dart` (email/password sign-up) — `firstName` (string), `middleInitial` (string), `lastName` (string), `fullName` (string), `mobileNumber` (string), `address` (string), `houseNo` (string), `street` (string), `purok` (string), `region` (string), `regionCode` (string), `province` (string), `provinceCode` (string), `municipality` (string), `municipalityCode` (string), `barangay` (string), `barangayCode` (string), `addressLat` (number, conditional), `addressLng` (number, conditional), `landmark` (string), `email` (string), `authEmail` (string), `createdAt` (timestamp). No `signInMethod` on this path.
  - `register_screen.dart` (`_registerWithGoogle`) — `firstName`, `middleInitial: ''`, `lastName`, `fullName`, `mobileNumber: ''`, `address: ''`, `email`, `authEmail`, `signInMethod: 'google'` (string), `createdAt`. This is the only path that sets `signInMethod`.
  - `edit_profile_screen.dart` (`_save`, via `.set(merge:true)`) — `firstName`, `middleInitial`, `lastName`, `fullName`, `mobileNumber`, `address`, `houseNo`, `street`, `purok`, `region`, `regionCode`, `province`, `provinceCode`, `municipality`, `municipalityCode`, `barangay`, `barangayCode`, `addressLat` (conditional), `addressLng` (conditional), `landmark`.
  - `notifications_screen.dart` (via `.set(merge:true)`) — `notificationPrefs` (map: `orderUpdates` bool, `promotions` bool, `appUpdates` bool, `shopReminders` bool).
  - `add_mobile_number_screen.dart` (via `.set(merge:true)`) — `mobileNumber` (string) only. This is the mandatory post-login "add your mobile number" gate for accounts missing one (e.g. Google sign-ups).
- Read by:
  - `services/customer_profile_cache.dart` (`CustomerProfileCache`) — one `.get()` of the full document, 5-minute in-memory cache, consumed by `edit_profile_screen.dart` (prefill), `notifications_screen.dart`, `home_screen.dart` (reads `mobileNumber` to decide whether to show the mandatory-mobile-number gate), `profile_tab.dart` (reads `notificationPrefs.appUpdates`).
  - `login_screen.dart` (`_loginWithGoogle`) and `register_screen.dart` (`_registerWithGoogle`) — existence check only (`.exists`), no field reads.
- FK-like fields: none pointing outward (this is the root entity). Its `uid` is the FK used by `orders.userId`, and implicitly by the `cart`/`addresses`/`notifications` subcollection paths below.

### `users/{uid}/cart/{cartItemId}`
- Read/write: both.
- Doc id: a deterministic slug, not an auto id — `cartItemId(productName, flavorName)` in `core/cart_helpers.dart`: `'$productName-${flavorName ?? 'default'}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')`.
- Written by `core/cart_helpers.dart` (`addProductToCart`, via `.set(merge:true)`) — `productId` (string?), `productName` (string), `imageUrl` (string?), `flavor` (string?), `unitPrice` (double), `wholesalePrice` (string?), `amount` (number, via `FieldValue.increment`), `updatedAt` (timestamp, `FieldValue.serverTimestamp()`).
- Updated/deleted by `cart_screen.dart` — `.update({'amount': newAmount})`, or `.delete()` if the new amount is ≤ 0 or on item removal.
- Read by `cart_screen.dart` (the cart list; reads `unitPrice`, `amount`, `productName`, `flavor`, `productId`, `imageUrl`), and the full raw doc data is passed straight through to `cart_order_confirmation_screen.dart` as the `items` list (so `wholesalePrice` reaches checkout that way, not via a named field access in `cart_screen.dart`).
- FK: `productId` → the Supabase product catalog (see Section 4), not a Firestore document.

### `users/{uid}/addresses/{autoId}`
- Read/write: both.
- Doc id: plain Firestore auto-id (`.add(...)`).
- Written (added) by `saved_addresses_screen.dart` (`_addAddress`) — `label` (string), `address` (string), `houseNo` (string), `street` (string), `purok` (string), `region`, `regionCode`, `province`, `provinceCode`, `municipality`, `municipalityCode`, `barangay`, `barangayCode` (all strings), `lat`/`lng` (number, conditional), `landmark` (string), `createdAt` (timestamp).
- Deleted by `_deleteAddress()` — `.delete()`. No `.update()` call exists in this file — editing an address is delete-and-re-add, not a patch.
- Read by `saved_addresses_screen.dart` (the list) and `core/cart_helpers.dart` (`pickDeliveryAddress`).

### `users/{uid}/notifications/{autoId}` — not actually used
- The only code that touches this subcollection is `core/notification_helpers.dart` (`addCustomerNotification`, `notifyCustomerOrderUpdate`), and that file itself has **zero callers** anywhere else in `lib/` (confirmed by grep). So in the current build nothing reads or writes this subcollection at all. The write code that exists, if it were called, would write `message` (string), `orderId` (string?), `read: false` (bool), `createdAt` (timestamp), and nothing ever flips `read` to `true`.
- Do not confuse this with the active `notificationPrefs` map stored directly on `users/{uid}` (written by `notifications_screen.dart`) — that's a 4-boolean settings toggle, not an inbox.

### `orders/{autoId}`
- Read/write: both.
- Doc id: plain Firestore auto-id (`orderRef = FirebaseFirestore.instance.collection('orders').doc()`), created up front and used as the transaction's write target.
- Created by `cart_order_confirmation_screen.dart` — the only reachable order-placement path. Full field list is in Section 3.
- Updated by `order_details_screen.dart`:
  - Cancel: `{'status': 'cancelled', 'cancelReason': reason}`.
  - Rate: `{'rating', 'feedback', 'ratedAt'}`.
  - Dismiss rating prompt: `{'ratingPromptDismissed': true}`.
- Status values this app ever **writes**: only `'pending'` (at creation) and `'cancelled'` (on cancel). `'approved'`, `'preparing'`, `'on_the_way'`, `'delivered'`, `'rejected'`, `'undeliverable'`/`'undelivered'` are read-only in this codebase — grepped for every literal and confirmed they appear only in comparisons/comments/dropdown labels, never in a `.set()`/`.update()` map. They're set by a separate staff/driver side not in this codebase.
- Read by:
  - `orders_tab.dart` — live query on active statuses (pending/approved/preparing/on_the_way) + one `.get()` by id for each order that just left that active set (the finished-order diff fix from earlier in this engagement).
  - `order_details_screen.dart` — live doc listener by id, plus the cancel/rate/dismiss updates above.
  - `home_screen.dart` (`_openOrderIfRequested`) — one `.get()` by id, used only to open the order screen from a push-notification deep link.
  - `profile_tab.dart` — three `.count().get()` aggregation queries, all scoped to the signed-in user: total orders, delivered orders, pending orders.
- FK-like fields: `userId` (→ `users/{uid}`), `items[].productId` (→ Supabase product catalog).

### `storeBanners/{id}` — read-only in this app
- Read by `services/banner_repository.dart` (`BannerRepository._fetch`, full-collection `.get()`, 5-minute cache) and the dead `core/banner_helpers.dart` function `storeBannersStream()` (zero callers).
- Fields read (`PromoBanner.fromMap`): `id`, `offer` (string), `description` (string), `imageUrl` (string), `scheduleStart` (timestamp), `scheduleEnd` (timestamp), `sortOrder` (number, default 0).
- Never written by this app. A write path (`saveStoreBanner()` in `banner_helpers.dart`) exists in source but has zero callers — dead code.

### `settings/storeBanner` — read, and also actively **deleted** by this app
- Read by `banner_repository.dart` (single-doc `.get()`, part of the same fetch as `storeBanners`) and `widgets/promo_banner_carousel.dart` (`_legacyData`).
- Fields read: `offer`, `description`, `imageUrl`, `scheduleStart`, `scheduleEnd`, `updatedAt`.
- **Deleted** by `core/banner_helpers.dart` (`deleteStoreBanner()`), called from `widgets/promo_banner_carousel.dart` (`_recomputeLiveBanners`) whenever this legacy doc is no longer valid and has a `scheduleEnd` set — the customer app self-cleans this admin-managed document client-side. Worth flagging explicitly for the ERD since it's a non-obvious write (a delete) from a screen that otherwise only reads.
- A write path (`saveStoreBanner()`) exists in source but has zero callers — dead code.

### `settings/appInfo` — read-only
- Read by `profile_tab.dart` (`_checkForUpdate`), one-shot `.get()`, gated behind `notificationPrefs.appUpdates`.
- Fields read: `latestVersion` (string), `updateMessage` (string?).
- Never written by this app.

### `employeeNotifications/{autoId}` — code exists, does not run in the live build
- See Section 2.

### `config/betaAnnouncement` — read-only
- Read by `services/beta_announcement_service.dart` (`BetaAnnouncementService.watch()`, live `.snapshots()` listener), consumed by `home_screen.dart`.
- Fields read: `enabled` (bool), `message` (string), `version` (number).
- Never written by this app.

### `products/{id}` — code exists, almost entirely dormant/dead
- Gated by `kUseSupabaseProducts = true` in `core/constants.dart`. With the flag true, the live product catalog is read/written through Supabase instead (Section 4).
- Code that still references this collection directly:
  - `services/product_repository.dart:94` — a Firestore listener, only active if the flag were `false` (dormant).
  - `core/product_helpers.dart:780` — `deleteProduct()`, zero callers (dead).
  - `core/cart_helpers.dart:85` — `seedProductCatalog()`, zero callers (dead).
  - `screens/customer/order_confirmation_screen.dart:255` — inside a screen nothing navigates to (dead).
- Fields these dormant/dead paths would write: `name` (string), `price` (string), `available` (bool), `flavors` (list of maps: `name`, `stock`, `price`, `wholesalePrice`, `available`).
- Not actually read or written anywhere in the live app today.

---

## 2. EMPLOYEE NOTIFICATIONS

- File: `screens/customer/cart_order_confirmation_screen.dart`, inside an `if (!kUseSupabaseStaffNotifications)` branch (~lines 517–523). Since `kUseSupabaseStaffNotifications = true` in `core/constants.dart`, **this branch never executes in the current build.**
- What it would write to `employeeNotifications/{autoId}` if it ran: `{'message': staffNotificationMessage, 'orderId': orderRef.id, 'createdAt': FieldValue.serverTimestamp()}` — **yes**, it includes the order id.
- What actually runs instead today (~lines 530–537): `SupabaseProductsApi.instance.notifyStaff(message: staffNotificationMessage!, orderId: orderRef.id)` — a Supabase call (action `app_notify_staff`, see Section 4), not a Firestore write.
- Also, `screens/customer/order_confirmation_screen.dart` (a dead/unreachable screen — nothing constructs `OrderConfirmationScreen(` anywhere except its own definition) writes `employeeNotifications` unconditionally with the same three fields, but this never executes because the screen is never navigated to.

---

## 3. ORDER DOCUMENTS

Full field list written at order creation, from `screens/customer/cart_order_confirmation_screen.dart` (the only reachable path — `txn.set(orderRef, {...})` inside a Firestore transaction):

- `userId` (string)
- `customerName` (string)
- `customerAddress` (string)
- `items` (list of maps), each entry: `productId`, `productName`, `imageUrl`, `flavor`, `amount`, `unitPrice`, `subtotal`
- `itemCount` (int)
- `itemsSubtotal` (double)
- `deliveryFee` (double)
- `fulfillmentType` (string: `'pickup'` or `'delivery'`)
- then, conditionally, exactly one of:
  - `pickupBranch` (string), or
  - `deliveryDistanceKm` (double) + `deliveryBranch` (string), or
  - `deliveryFeeUnresolved: true` (bool)
- conditionally `deliveryLat` (double) + `deliveryLng` (double) + `deliveryMapUrl` (string)
- `total` (double)
- `status` (string, `'pending'` at creation)
- `estimatedDelivery` (timestamp)
- `createdAt` (timestamp, `FieldValue.serverTimestamp()`)

Later updates, all from `order_details_screen.dart`:
- Cancel: `status: 'cancelled'`, `cancelReason` (string).
- Rate: `rating` (number), `feedback` (string), `ratedAt` (timestamp).
- Dismiss rating prompt: `ratingPromptDismissed: true` (bool).

Dead screen's version (`order_confirmation_screen.dart`, never reachable): structurally similar but writes a single-item `items` list, and writes to `products`/`employeeNotifications` unconditionally rather than behind the feature flags.

---

## 4. SUPABASE

### `store-api` Edge Function — `services/supabase_products.dart`
All calls go through `_call(body)`, which POSTs to `kSupabaseStoreApiUrl` with headers `Content-Type`, `apikey` (`kSupabasePublishableKey`), `x-firebase-token` (the signed-in user's Firebase ID token):

| Action | Sends | Returns |
|---|---|---|
| `app_list_products` | `{offset, limit}` (limit default 1000) | `{products, done}` |
| `app_get_products` | `{ids}` | `{products}` |
| `app_best_sellers` | `{limit}` (default 20) | `{ids}` — used by `fetchBestSellingProductIds()` in `core/cart_helpers.dart` |
| `app_apply_sale` | `{items: [{id, variant, qty}, ...], ref}` | throws `SupabaseApiException('insufficient_stock', details)` on failure; used during checkout stock deduction |
| `app_restock` | `{items?, ref}` | best-effort, never throws; treats `'nothing_to_restock'` as success; used on order cancel |
| `app_notify_staff` | `{message, orderId?}` | best-effort, never throws; the live staff-notification mechanism (see Section 2) |

### `login-guard` Edge Function — `services/login_guard_api.dart`
A separate function from `store-api`. Called with only an `apikey` header (no Firebase ID token — used before the user is signed in):

| Action | Sends | Returns |
|---|---|---|
| `customer_resolve` | `{action, mobile}` | the matching email, or `null` if `data['found'] != true` — used by `login_screen.dart` to turn a typed mobile number into an email before `signInWithEmailAndPassword` |
| `customer_taken` | `{action, email?, mobile?}` | `(emailTaken, mobileTaken)` — used by `register_screen.dart` (pre-signup check) and `add_mobile_number_screen.dart` (before saving a newly-added mobile number) |

Doc comment in `login_guard_api.dart` explains why this function exists at all: "Firestore's `users` collection is no longer publicly readable — security rules now only let a signed-in customer read their own `users/{uid}` document," so these lookups can't be done as plain Firestore reads pre-sign-in.

No other direct Supabase table or function usage was found — there is no `supabase_flutter`/`SupabaseClient` import anywhere in `lib/` (grepped). Every Supabase interaction in this app is a plain HTTP call to one of these two Edge Functions.

---

## 5. LEGACY COLLECTIONS

Zero matches anywhere in `lib/` for all of these — **not found**:
`otpVerifications`, `resetEmailAttempts`, `loginAttempts`, `staffCode`, `posSales`, `posRefunds`, `stockMovements`, `salesDaily`, `notificationStatus`, `driverLocations`.

`products` **is** present in the code, but it's dormant/dead as described in Section 1 — not a legacy leftover in active use, just an unreachable/flag-gated code path.

Every other collection named in your allowed list (`users`, `users/{uid}/cart`, `users/{uid}/addresses`, `users/{uid}/notifications`, `orders`, `storeBanners`, `settings`, `employeeNotifications`) is accounted for in Section 1.

---

## 6. AUTH

- **Email + password** — standard Firebase Auth (`createUserWithEmailAndPassword` / `signInWithEmailAndPassword`), in `register_screen.dart` and `login_screen.dart`.
- **Google** — Firebase Auth's Google provider, in `register_screen.dart` (`_registerWithGoogle`) and `login_screen.dart` (`_loginWithGoogle`). Only the sign-up path writes `signInMethod: 'google'` on `users/{uid}`. Login never creates a user document — if `users/{uid}` doesn't exist yet, `_loginWithGoogle` signs the user back out and shows "No account found... Please register first."
- **Mobile number** — **not** a distinct Firebase Auth method and **not** native Firebase phone/OTP auth (there's no `verifyPhoneNumber` call anywhere in `lib/`, consistent with `otpVerifications` being unused). It's a client-side convenience layered on top of email/password auth:
  1. `login_screen.dart`'s `_login()` checks whether the typed input contains `'@'`.
  2. If not, it calls `LoginGuardApi.instance.resolveMobileToEmail(mobile)` (the `login-guard` function's `customer_resolve` action) to look up the account's real email.
  3. It then calls the ordinary `FirebaseAuth.instance.signInWithEmailAndPassword(email, password)` with that resolved email.
  - The mobile number itself is stored as a plain string field, `mobileNumber`, on `users/{uid}` — never as a Firebase Auth identity/provider.

---

## Summary of document-id strategies across the app

| Collection | Id strategy |
|---|---|
| `users/{uid}` | Firebase Auth uid |
| `users/{uid}/cart/{cartItemId}` | deterministic slug of productName + flavor |
| `users/{uid}/addresses/{autoId}` | Firestore auto-id |
| `users/{uid}/notifications/{autoId}` | Firestore auto-id (code path unused) |
| `orders/{autoId}` | Firestore auto-id |
| `employeeNotifications/{autoId}` | Firestore auto-id (code path dormant) |
| `storeBanners/{id}`, `settings/*`, `config/*` | fixed/well-known doc names, or ids owned by a system outside this app |
