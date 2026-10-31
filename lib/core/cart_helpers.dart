import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/customer/product_options_sheet.dart';
import '../screens/customer/address_picker_screen.dart';
import '../services/supabase_products.dart';
import 'product_helpers.dart';
import 'read_counter.dart';

// In-memory, 5-minute cache for fetchBestSellingProductIds() below - see
// its own doc comment for why this exists. Keyed by topN so two callers
// asking for different counts (there's only ever been one in practice -
// both call sites below use the default) never hand each other a
// differently-sized result.
class _BestSellingEntry {
  final Set<String> ids;
  final DateTime fetchedAt;
  const _BestSellingEntry(this.ids, this.fetchedAt);
}

const Duration _bestSellingTtl = Duration(minutes: 5);
final Map<int, _BestSellingEntry> _bestSellingCache = {};
final Map<int, Future<Set<String>>> _bestSellingInFlight = {};

/// Which product ids are "best selling" right now, by total units sold
/// across every order ever placed.
///
/// This was the actual cause of a Firestore read spike (a routine ~100-read
/// app tour costing ~14,000 reads instead): both call sites
/// (home_tab.dart's Featured section, all_products_screen.dart) invoke this
/// from inside a `FutureBuilder`'s `future:` parameter, which re-evaluates
/// the expression - and therefore re-ran this whole, unfiltered,
/// unlimited `.get()` of the ENTIRE orders collection - on every rebuild of
/// that subtree: every product-catalog refresh (the ~3-minute periodic
/// timer in product_repository.dart, which runs continuously once Home has
/// ever registered a product screen as visible), every app resume while a
/// product screen is visible, and in all_products_screen.dart's case,
/// every single keystroke while searching. On a store with a non-trivial
/// orders history, that's a full-collection read dozens of times an hour
/// for data that only meaningfully changes as fast as new orders come in.
///
/// Now cached for 5 minutes (same TTL as [CustomerProfileCache] and
/// [BannerRepository], for the same reason), with concurrent callers
/// sharing one in-flight fetch instead of firing a second one - a rebuild,
/// a keystroke, or a catalog refresh landing inside that window reuses the
/// cached result instead of re-reading the whole collection.
Future<Set<String>> fetchBestSellingProductIds({int topN = 5}) async {
  final _BestSellingEntry? cached = _bestSellingCache[topN];
  if (cached != null &&
      DateTime.now().difference(cached.fetchedAt) < _bestSellingTtl) {
    return cached.ids;
  }

  final Future<Set<String>>? inFlight = _bestSellingInFlight[topN];
  if (inFlight != null) return inFlight;

  final Future<Set<String>> future = _fetchBestSellingProductIds(topN);
  _bestSellingInFlight[topN] = future;
  try {
    return await future;
  } finally {
    _bestSellingInFlight.remove(topN);
  }
}

Future<Set<String>> _fetchBestSellingProductIds(int topN) async {
  final ordersSnapshot = await FirebaseFirestore.instance
      .collection('orders')
      .get();
  ReadCounter.log(
    'fetchBestSellingProductIds:orders',
    ordersSnapshot.docs.length,
  );
  final Map<String, int> soldCounts = {};

  for (final doc in ordersSnapshot.docs) {
    final data = doc.data();
    final String? productId = data['productId'] as String?;
    if (productId == null) continue;
    final int amount = (data['amount'] as num?)?.toInt() ?? 0;
    soldCounts[productId] = (soldCounts[productId] ?? 0) + amount;
  }

  final sorted = soldCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final Set<String> result = sorted.take(topN).map((e) => e.key).toSet();
  _bestSellingCache[topN] = _BestSellingEntry(result, DateTime.now());
  return result;
}

Future<void> seedProductCatalog() async {
  final products = FirebaseFirestore.instance.collection('products');

  await products.doc('lucky_me_pancit_canton').set({
    'name': 'Lucky Me Pancit Canton',
    'price': '₱17.00',
    'available': true,
    'flavors': [
      {'name': 'Red (Chili Mansi)', 'stock': 60, 'available': true},
      {'name': 'Orange (Sweet Style)', 'stock': 45, 'available': true},
      {'name': 'Yellow (Original)', 'stock': 80, 'available': true},
      {'name': 'Green (Kalamansi)', 'stock': 0, 'available': false},
    ],
  });

  await products.doc('555_sardines_tomato_sauce').set({
    'name': '555 Sardines in Tomato Sauce',
    'price': '₱32.00',
    'available': true,
    'stockCount': 180,
    'flavors': <Map<String, dynamic>>[],
  });
}

/// Reads the current stock for the item being bought and returns the
/// Firestore update that deducts [amount] from it - or null when there's
/// nothing to deduct (see below), so the caller knows to skip writing
/// anything for this product rather than clobbering it with an empty map.
///
/// A missing/non-numeric stock value (`stock` on the flavor, or
/// `stockCount` on a simple product) means the admin side isn't tracking
/// a count for this item at all - a 4,500+-row CSV import, in particular,
/// may leave it unset entirely. That's different from an explicit `0`,
/// which means "tracked, and currently empty": only the explicit-zero
/// case blocks the purchase or gets decremented. An untracked item is
/// always purchasable and is left untouched (still untracked) afterwards
/// - it must never be silently treated as "0 in stock" and block
/// checkout, which is what happened before this.
Future<Map<String, dynamic>?> readStockDeduction(
  Transaction txn,
  DocumentReference<Map<String, dynamic>> productRef,
  String? flavorName,
  int amount,
) async {
  final snapshot = await txn.get(productRef);
  final data = snapshot.data();
  if (data == null) {
    throw Exception('This product is no longer available.');
  }

  final flavors =
      (data['flavors'] as List?)
          ?.map((f) => Map<String, dynamic>.from(f as Map))
          .toList() ??
      const <Map<String, dynamic>>[];

  if (flavors.isNotEmpty && flavorName != null) {
    final index = flavors.indexWhere((f) => f['name'] == flavorName);
    if (index == -1) {
      throw Exception('$flavorName is no longer available.');
    }
    final dynamic rawStock = flavors[index]['stock'];
    if (rawStock is! num) return null;
    final int currentStock = rawStock.toInt();
    if (currentStock < amount) {
      throw Exception('Only $currentStock pcs of $flavorName left.');
    }
    final int newStock = currentStock - amount;
    final updatedFlavors = List<Map<String, dynamic>>.from(flavors);
    updatedFlavors[index] = {
      ...updatedFlavors[index],
      'stock': newStock,
      'available': newStock > 0,
    };
    return {'flavors': updatedFlavors};
  }

  final dynamic rawStock = data['stockCount'];
  if (rawStock is! num) return null;
  final int currentStock = rawStock.toInt();
  if (currentStock < amount) {
    throw Exception('Only $currentStock pcs of ${data['name']} left.');
  }
  final int newStock = currentStock - amount;
  return {'stockCount': newStock, 'available': newStock > 0};
}

/// Best-effort read of the product/variant the backend flagged as short on
/// stock, for the "Only N pcs left" message below. The migration spec only
/// pins the error code down to 'insufficient_stock' "with product/variant
/// info" - not an exact field layout - so this tries a few plausible
/// shapes rather than assuming one, and falls back to a generic message
/// instead of throwing if none of them match (this already runs inside a
/// catch block, so a second failure here must never replace a clear error
/// with a crash).
String _insufficientStockMessage(
  Map<String, dynamic>? details,
  Map<String, Map<String, dynamic>> freshProductsById,
) {
  try {
    dynamic info = details?['item'] ?? details?['product'];
    if (info == null && details?['items'] is List) {
      final items = details!['items'] as List;
      if (items.isNotEmpty) info = items.first;
    }
    if (info is Map) {
      final String? id = info['id'] as String?;
      final String? name =
          (info['name'] as String?) ??
          (id != null ? (freshProductsById[id]?['name'] as String?) : null);
      final dynamic left = info['available'] ?? info['stock'] ?? info['stockLeft'];
      if (name != null && left is num) {
        return 'Only ${left.toInt()} pcs of $name left.';
      }
      if (name != null) return '$name no longer has enough stock.';
    }
  } catch (_) {
    // Falls through to the generic message below.
  }
  return 'One or more items in your order no longer have enough stock.';
}

/// Supabase-backed counterpart to [readStockDeduction] +
/// [resolveLiveUnitPrice] above, used for checkout when
/// kUseSupabaseProducts is on (see cart_order_confirmation_screen.dart's
/// _confirmOrder, which branches on that flag). Each entry in [items] is
/// one cart/order line: {productId, flavor, amount, unitPrice} - unitPrice
/// is only the fallback used if a fresh price can't be resolved (e.g. the
/// product or flavor was removed since the cart snapshot was taken).
///
/// Does both of app_get_products/app_apply_sale's jobs in one call: a
/// fresh read re-validates price (including the wholesale tier, since
/// amount is known here) exactly the way resolveLiveUnitPrice() used to
/// inside a Firestore transaction, then app_apply_sale deducts stock,
/// keyed on [orderRef] so a retried call (e.g. after a timeout where the
/// first attempt actually went through) never double-deducts. Returns the
/// resolved unit prices in the same order as [items]. Throws a plain
/// Exception with a customer-facing message on insufficient stock, same
/// style as [readStockDeduction], so the checkout screen's existing
/// catch-and-show-SnackBar code doesn't need to know which backend this
/// came from.
Future<List<double>> deductStockAndResolvePricesSupabase({
  required List<Map<String, dynamic>> items,
  required String orderRef,
}) async {
  final List<String> ids = items
      .map((item) => item['productId'] as String?)
      .whereType<String>()
      .toSet()
      .toList();

  final List<Map<String, dynamic>> fresh = await SupabaseProductsApi.instance
      .getProducts(ids);
  final Map<String, Map<String, dynamic>> freshById = {
    for (final product in fresh) (product['id'] as String): product,
  };

  final List<double> liveUnitPrices = [];
  final List<CheckoutItem> checkoutItems = [];

  for (final item in items) {
    final String? productId = item['productId'] as String?;
    final String? flavorName = item['flavor'] as String?;
    final int amount = (item['amount'] as num?)?.toInt() ?? 0;
    final double fallback = (item['unitPrice'] as num?)?.toDouble() ?? 0;

    liveUnitPrices.add(
      liveUnitPriceFromProductDoc(
        productId != null ? freshById[productId] : null,
        flavorName,
        amount,
        fallback,
      ),
    );
    if (productId != null && amount > 0) {
      checkoutItems.add(
        CheckoutItem(id: productId, variant: flavorName, qty: amount),
      );
    }
  }

  if (checkoutItems.isNotEmpty) {
    try {
      await SupabaseProductsApi.instance.applySale(
        items: checkoutItems,
        ref: orderRef,
      );
    } on SupabaseApiException catch (e) {
      if (e.code == 'insufficient_stock') {
        throw Exception(_insufficientStockMessage(e.details, freshById));
      }
      throw Exception('Could not place order. Please try again.');
    }
  }

  return liveUnitPrices;
}

/// Compensates a successful [deductStockAndResolvePricesSupabase] call when
/// something downstream (the Firestore order write) failed afterwards -
/// see SupabaseProductsApi.restock()'s doc comment for why this is
/// best-effort/never throws.
Future<void> compensateRestockSupabase({
  required List<Map<String, dynamic>> items,
  required String orderRef,
}) async {
  final List<CheckoutItem> checkoutItems = items
      .where((item) => item['productId'] != null)
      .map(
        (item) => CheckoutItem(
          id: item['productId'] as String,
          variant: item['flavor'] as String?,
          qty: (item['amount'] as num?)?.toInt() ?? 0,
        ),
      )
      .toList();
  if (checkoutItems.isEmpty) return;
  await SupabaseProductsApi.instance.restock(
    items: checkoutItems,
    ref: orderRef,
  );
}

String cartItemId(String productName, String? flavorName) {
  final key = '$productName-${flavorName ?? 'default'}';
  return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

Future<void> addProductToCart({
  required Map<String, dynamic> product,
  required Map<String, dynamic>? flavor,
  required int amount,
  required double unitPrice,
  // Cached alongside the item so the quantity stepper on the Confirm
  // Order screen can switch to wholesale pricing the instant the amount
  // crosses kWholesaleMinimumQuantity, without a network round-trip - see
  // that screen's _updateAmount(). Null when this product/flavor has no
  // wholesale price set.
  String? wholesalePrice,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception('Not signed in');
  }

  final String? productId = product['id'] as String?;
  final String productName = product['name'] as String? ?? '';
  final String? flavorName = flavor?['name'] as String?;
  final String? flavorImage = flavor?['imageUrl'] as String?;
  final String? imageUrl = (flavorImage != null && flavorImage.isNotEmpty)
      ? flavorImage
      : product['imageUrl'] as String?;
  final String docId = cartItemId(productName, flavorName);

  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('cart')
      .doc(docId);

  await ref.set({
    'productId': productId,
    'productName': productName,
    'imageUrl': imageUrl,
    'flavor': flavorName,
    'unitPrice': unitPrice,
    'wholesalePrice': wholesalePrice,
    'amount': FieldValue.increment(amount),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

void showProductOptions(
  BuildContext context, {
  required Map<String, dynamic> product,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Product options',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, anim1, anim2) {
      return ProductOptionsSheet(product: product);
    },
    transitionBuilder: (context, anim1, anim2, child) {
      final double blur = 8 * anim1.value;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Combines a plain address with an optional landmark into the single
/// string used everywhere a delivery address is picked, stored on an
/// order, or shown to whoever fulfills it - kept in one place so a
/// landmark is treated the same way wherever an address flows through.
String combineAddressAndLandmark(String address, String? landmark) {
  final String trimmedLandmark = landmark?.trim() ?? '';
  if (trimmedLandmark.isEmpty) return address;
  return '$address (Landmark: $trimmedLandmark)';
}

/// Result of [pickDeliveryAddress] - the combined address text plus the
/// exact pinned coordinates behind it (read straight from the profile or
/// saved-address doc, no re-geocoding), when that address was captured
/// through the map picker. Null lat/lng means only the text is known
/// (e.g. an address typed in before this fix, or edited manually), and
/// checkout should fall back to its own approximate geocoding for that
/// case.
class PickedDeliveryAddress {
  final String address;
  final double? lat;
  final double? lng;
  const PickedDeliveryAddress({required this.address, this.lat, this.lng});
}

Future<PickedDeliveryAddress?> pickDeliveryAddress(
  BuildContext context,
  String currentAddress,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

  final userDoc = await userRef.get();
  ReadCounter.log('pickDeliveryAddress:users', userDoc.exists ? 1 : 0);
  String profileAddress = (userDoc.data()?['address'] as String?) ?? '';
  final String profileLandmark =
      (userDoc.data()?['landmark'] as String?) ?? '';
  // Exact pin coordinates for the profile address, when it was captured
  // via the map picker. Cleared below whenever the address text is
  // edited manually, since the pin no longer matches the text.
  double? profileLat = (userDoc.data()?['addressLat'] as num?)?.toDouble();
  double? profileLng = (userDoc.data()?['addressLng'] as num?)?.toDouble();

  final addressesSnapshot = await userRef
      .collection('addresses')
      .orderBy('createdAt', descending: true)
      .get();
  ReadCounter.log(
    'pickDeliveryAddress:addresses',
    addressesSnapshot.docs.length,
  );
  final List<Map<String, dynamic>> addresses = addressesSnapshot.docs
      .map((doc) => {'id': doc.id, ...doc.data()})
      .toList();

  if (!context.mounted) return null;

  return showModalBottomSheet<PickedDeliveryAddress>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // If the profile address text happens to match one of the saved
          // custom addresses, only highlight one entry (the specific saved
          // address) so the picker never shows two rows selected at once.
          final bool profileMatchesSavedAddress = addresses.any(
            (a) => (a['address'] as String? ?? '') == profileAddress,
          );
          // What actually gets returned/compared for the Profile Address
          // row - the raw address plus its landmark folded in, so the
          // landmark rides along through the order automatically without
          // needing its own field threaded through the whole checkout
          // flow.
          final String combinedProfileAddress = combineAddressAndLandmark(
            profileAddress,
            profileLandmark,
          );

          // Routed through the map picker (not a plain text dialog) so a
          // "quick edit" here can never leave the profile address without
          // exact coordinates - that gap was exactly what let addresses
          // slip through to the unreliable, Nominatim-dependent delivery
          // fee fallback instead of the fast, exact coordinate-based one.
          Future<void> editProfileAddress() async {
            final PickedAddress? picked = await Navigator.push<PickedAddress>(
              context,
              MaterialPageRoute(
                builder: (context) => AddressPickerScreen(
                  initialAddress: profileAddress.trim().isEmpty
                      ? null
                      : profileAddress.trim(),
                ),
              ),
            );
            if (picked == null || picked.address.trim().isEmpty) return;
            await userRef.set({
              'address': picked.address,
              'addressLat': picked.lat,
              'addressLng': picked.lng,
            }, SetOptions(merge: true));
            profileAddress = picked.address;
            profileLat = picked.lat;
            profileLng = picked.lng;
            setSheetState(() {});
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Choose Delivery Address',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (profileAddress.trim().isNotEmpty)
                      // Built from two independent, side-by-side tap targets
                      // (rather than ListTile's onTap + trailing combo) so
                      // selecting the address and editing it can never
                      // intercept each other's taps.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(
                                  sheetContext,
                                  PickedDeliveryAddress(
                                    address: combinedProfileAddress,
                                    lat: profileLat,
                                    lng: profileLng,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    4,
                                    10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        (currentAddress ==
                                                    combinedProfileAddress &&
                                                !profileMatchesSavedAddress)
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        color: const Color(0xFF2E6B3E),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Profile Address',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              profileAddress,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            if (profileLandmark
                                                .trim()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Landmark: $profileLandmark',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFF2E6B3E),
                            ),
                            tooltip: 'Edit profile address',
                            onPressed: editProfileAddress,
                          ),
                        ],
                      )
                    else
                      ListTile(
                        leading: const Icon(
                          Icons.add_location_alt_outlined,
                          color: Color(0xFF2E6B3E),
                        ),
                        title: const Text('Add Profile Address'),
                        onTap: editProfileAddress,
                      ),
                    if (addresses.isNotEmpty) const Divider(height: 1),
                    ...addresses.map((data) {
                      final String label = data['label'] as String? ?? 'Address';
                      final String address = data['address'] as String? ?? '';
                      final String landmark =
                          data['landmark'] as String? ?? '';
                      final String combinedAddress = combineAddressAndLandmark(
                        address,
                        landmark,
                      );
                      final bool isSelected =
                          currentAddress == combinedAddress;
                      final double? lat = (data['lat'] as num?)?.toDouble();
                      final double? lng = (data['lng'] as num?)?.toDouble();
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: const Color(0xFF2E6B3E),
                        ),
                        title: Text(label),
                        subtitle: Text(
                          landmark.trim().isEmpty
                              ? address
                              : '$address\nLandmark: $landmark',
                        ),
                        onTap: () => Navigator.pop(
                          sheetContext,
                          PickedDeliveryAddress(
                            address: combinedAddress,
                            lat: lat,
                            lng: lng,
                          ),
                        ),
                      );
                    }),
                    const Divider(height: 1),
                    // Managing saved addresses (adding/removing) now lives
                    // only in the Profile section, so this sheet is just
                    // for picking one - no separate "Add New Address" here
                    // to avoid two different places that do the same
                    // thing.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'To add a new address, go to your profile.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
