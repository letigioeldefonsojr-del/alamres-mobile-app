import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Thrown by every [SupabaseProductsApi] call on a non-ok response. [code]
/// is whatever string the Edge Function put in `error` (e.g.
/// 'insufficient_stock', 'not_signed_in') - callers match on this rather
/// than parsing prose.
class SupabaseApiException implements Exception {
  final String code;
  final Map<String, dynamic>? details;
  const SupabaseApiException(this.code, {this.details});
  @override
  String toString() => code;
}

/// One line item for [SupabaseProductsApi.applySale]/[restock] - a plain
/// product (no flavor) leaves [variant] null.
class CheckoutItem {
  final String id;
  final String? variant;
  final int qty;
  const CheckoutItem({required this.id, this.variant, required this.qty});

  Map<String, dynamic> toJson() => {'id': id, 'variant': variant, 'qty': qty};
}

String _formatPeso(num value) => '₱${value.toStringAsFixed(2)}';

/// `extra`'s JSON has no Timestamp type of its own, but a few fields that
/// live inside it are read elsewhere via `as Timestamp?` / `is Timestamp`
/// (isDiscountActive() in product_helpers.dart; the Best Sellers/Featured
/// sort in home_tab.dart and featured_products_screen.dart) - so an
/// ISO-string value coming back from Supabase for one of those has to be
/// converted to a real [Timestamp] here, once, or those casts would throw
/// instead of just returning null the way a genuinely-absent field does.
void _coerceTimestampField(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) map[key] = Timestamp.fromDate(parsed);
  }
}

/// Converts one Supabase `products` row (snake_case, numeric prices) into
/// the same Map shape the rest of the app already works with from a
/// Firestore product document (peso-formatted price strings, `stockCount`,
/// etc.) - the point is that product_card.dart, product_helpers.dart, the
/// options sheet and everything else downstream need little to no changes
/// to work with either source. `extra` is spread in first (it carries the
/// "leftover" fields this app still reads directly - imageUrl, bestSeller,
/// featured/featuredAt, discount fields, salesTier) so the explicit fields
/// below always win on any accidental name collision.
Map<String, dynamic> productFromRow(Map<String, dynamic> row) {
  final Map<String, dynamic> extra = (row['extra'] is Map)
      ? Map<String, dynamic>.from(row['extra'] as Map)
      : <String, dynamic>{};
  final Map<String, dynamic> variantPrices = (row['variant_prices'] is Map)
      ? Map<String, dynamic>.from(row['variant_prices'] as Map)
      : <String, dynamic>{};

  final List<dynamic> rawFlavors = (row['flavors'] as List?) ?? const [];
  final List<Map<String, dynamic>> flavors = rawFlavors.map((f) {
    final Map<String, dynamic> flavor = Map<String, dynamic>.from(f as Map);
    final String? name = flavor['name'] as String?;
    final num? price = flavor['price'] as num?;
    final num? stock = flavor['stock'] as num?;
    // Per-variant wholesale pricing isn't a field on the flavor row itself
    // - it's looked up from the product's own variant_prices map by name.
    final num? wholesale = (name != null && variantPrices[name] is num)
        ? variantPrices[name] as num
        : null;
    return <String, dynamic>{
      'name': name,
      'price': price != null ? _formatPeso(price) : null,
      'stock': stock,
      'available': flavor['available'] as bool? ?? true,
      if (wholesale != null) 'wholesalePrice': _formatPeso(wholesale),
    };
  }).toList();

  final num? price = row['price'] as num?;
  final num? wholesalePrice = row['wholesale_price'] as num?;

  final Map<String, dynamic> product = <String, dynamic>{
    ...extra,
    'id': row['id'],
    'name': row['name'],
    'category': row['category'],
    'price': price != null ? _formatPeso(price) : '₱0.00',
    if (wholesalePrice != null) 'wholesalePrice': _formatPeso(wholesalePrice),
    'stockCount': row['stock_count'],
    'available': row['available'] as bool? ?? true,
    'flavors': flavors,
    if (row['barcode'] != null) 'barcode': row['barcode'],
    if (row['barcodes'] != null) 'barcodes': row['barcodes'],
  };

  _coerceTimestampField(product, 'featuredAt');
  _coerceTimestampField(product, 'discountStart');
  _coerceTimestampField(product, 'discountEnd');
  final String? createdAtIso = row['created_at'] as String?;
  if (createdAtIso != null) {
    final DateTime? parsed = DateTime.tryParse(createdAtIso);
    if (parsed != null) product['createdAt'] = Timestamp.fromDate(parsed);
  }

  return product;
}

/// The only place this app talks to Supabase - everything goes through the
/// single `store-api` Edge Function (see kUseSupabaseProducts in
/// constants.dart for why this exists at all). Every request carries the
/// signed-in customer's Firebase ID token; the function is what actually
/// decides whether to answer, not anything client-side here.
class SupabaseProductsApi {
  SupabaseProductsApi._();
  static final SupabaseProductsApi instance = SupabaseProductsApi._();

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SupabaseApiException('not_signed_in');
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null) {
      throw const SupabaseApiException('not_signed_in');
    }

    final response = await http
        .post(
          Uri.parse(kSupabaseStoreApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'apikey': kSupabasePublishableKey,
            'x-firebase-token': idToken,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SupabaseApiException('bad_response');
    }
    if (decoded['ok'] != true) {
      throw SupabaseApiException(
        (decoded['error'] as String?) ?? 'unknown_error',
        details: decoded,
      );
    }
    return decoded;
  }

  /// One page of the catalog, already converted via [productFromRow].
  /// [ProductRepository] pages through with [offset] until `done` comes
  /// back true.
  Future<({List<Map<String, dynamic>> products, bool done})> listProducts({
    required int offset,
    int limit = 1000,
  }) async {
    final data = await _call({
      'action': 'app_list_products',
      'offset': offset,
      'limit': limit,
    });
    final List<Map<String, dynamic>> products = ((data['products'] as List?) ?? const [])
        .map((row) => productFromRow(row as Map<String, dynamic>))
        .toList();
    return (products: products, done: data['done'] == true);
  }

  /// Fresh copies of specific products, by id - used wherever a cached
  /// catalog snapshot isn't authoritative enough: the cart's live price
  /// display, and checkout's price/stock re-validation right before
  /// placing an order.
  Future<List<Map<String, dynamic>>> getProducts(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final data = await _call({'action': 'app_get_products', 'ids': ids});
    return ((data['products'] as List?) ?? const [])
        .map((row) => productFromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Up to [limit] product ids currently selling best, computed server-side
  /// (against the backend's own order/sales data, not this client's
  /// Firestore access) by the `app_best_sellers` action - see
  /// fetchBestSellingProductIds() in cart_helpers.dart, the only caller.
  /// This replaced that function's old `.get()` of the entire `orders`
  /// collection, which was the actual cause of a Firestore read spike.
  Future<List<String>> bestSellingProductIds({int limit = 20}) async {
    final data = await _call({
      'action': 'app_best_sellers',
      'limit': limit,
    });
    return ((data['ids'] as List?) ?? const [])
        .map((id) => id.toString())
        .toList();
  }

  /// Deducts stock for a placed order. [ref] is the new order's Firestore
  /// id - the backend uses it to make this idempotent, so a retried call
  /// (e.g. after a timeout where the first attempt actually succeeded)
  /// never double-deducts. Throws [SupabaseApiException] with code
  /// 'insufficient_stock' when there isn't enough left; the caller shows
  /// that as the usual "Only N pcs left" message and does not create the
  /// order.
  Future<void> applySale({
    required List<CheckoutItem> items,
    required String ref,
  }) async {
    await _call({
      'action': 'app_apply_sale',
      'items': items.map((i) => i.toJson()).toList(),
      'ref': ref,
    });
  }

  /// Compensates a successful [applySale] when something downstream (the
  /// Firestore order write) failed afterwards - puts the deducted stock
  /// back. Best-effort and never throws: in that checkout-failure case the
  /// order was never created either way, and there's nothing more useful
  /// this app can do with a second failure here than leave the stock
  /// under-counted until it's next reconciled.
  ///
  /// [items] is omitted when giving back everything a whole order
  /// deducted, rather than compensating one specific checkout attempt -
  /// see order_details_screen.dart's cancel flow, which calls this with
  /// just [ref] (the order id) and lets the server work out what that
  /// order's own app_apply_sale call took. The server only restocks a
  /// given [ref] once; a repeat call (the order was already restocked)
  /// comes back as an error this treats as a success, not a real failure,
  /// same best-effort/never-throws reasoning as above.
  Future<void> restock({
    List<CheckoutItem>? items,
    required String ref,
  }) async {
    try {
      await _call({
        'action': 'app_restock',
        if (items != null) 'items': items.map((i) => i.toJson()).toList(),
        'ref': ref,
      });
    } on SupabaseApiException catch (e) {
      // Nothing left to restock for this ref (e.g. already restocked, or
      // nothing was ever deducted for it) - not a real failure.
      if (e.code == 'nothing_to_restock') return;
      debugPrint('restock failed: $e');
    } catch (e) {
      // Best-effort - see doc comment above. Logged (not surfaced to the
      // customer) so a genuine, recurring failure is still discoverable.
      debugPrint('restock failed: $e');
    }
  }

  /// Sends a staff notification - what lights up the admin site's
  /// notification bell - via Supabase instead of writing a Firestore
  /// `employeeNotifications` document (see kUseSupabaseStaffNotifications
  /// in constants.dart). Called after the order it's about has already
  /// been saved, so it only ever reports something that really happened;
  /// best-effort and never throws either way, since a failed notification
  /// must never block or fail the order itself - a failure here just means
  /// staff don't get pinged for this one, which is logged for debugging
  /// and otherwise silently swallowed.
  Future<void> notifyStaff({required String message, String? orderId}) async {
    try {
      await _call({
        'action': 'app_notify_staff',
        'message': message,
        if (orderId != null) 'orderId': orderId,
      });
    } catch (e) {
      debugPrint('notifyStaff failed: $e');
    }
  }
}
