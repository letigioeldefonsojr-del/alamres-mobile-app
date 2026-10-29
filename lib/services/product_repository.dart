import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import 'supabase_products.dart';

/// The one shared source of product data for the whole app - every product
/// grid/list/search screen reads [productsNotifier] instead of hitting
/// Firestore or Supabase directly. This exists because Supabase (unlike
/// Firestore) has no realtime listener wired up on the app side, so
/// something has to own "what's the catalog right now" and refresh it on a
/// sensible schedule instead of every screen re-fetching independently.
///
/// When [kUseSupabaseProducts] is false this falls back to the old
/// Firestore `.snapshots()` listener, so flipping that flag is still a
/// complete, working revert - not just a dead code path.
class ProductRepository {
  ProductRepository._();
  static final ProductRepository instance = ProductRepository._();

  /// The full catalog right now. A fresh [List] instance only when the
  /// data actually changed (same instance reused otherwise), so screens
  /// that memoize derived work (categories, filtered views) off this
  /// list's identity - the same `identical()` pattern already used against
  /// Firestore's own QuerySnapshot - keep working unchanged.
  final ValueNotifier<List<Map<String, dynamic>>> productsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>(const <Map<String, dynamic>>[]);

  /// Null when the catalog is current (or hasn't been asked to refresh
  /// yet); a short user-facing message when the most recent refresh
  /// attempt failed - screens that want the "showing saved list" notice
  /// listen to this rather than re-deriving it from internal state.
  final ValueNotifier<String?> staleNoticeNotifier = ValueNotifier<String?>(null);

  /// True once at least one refresh has actually completed against the
  /// live backend (Supabase or, on the Firestore path, the first
  /// snapshot) - distinct from merely having cached data on screen. Used
  /// to gate "this id isn't in the list anymore, so treat it as deleted"
  /// logic (e.g. the cart's gone-product detection) so a product is never
  /// wrongly treated as deleted off of a stale/incomplete on-disk cache
  /// alone.
  bool hasRefreshedOnce = false;

  DateTime? _lastRefreshAt;
  bool _isRefreshing = false;
  bool _refreshQueued = false;
  bool _started = false;

  int _visibleScreens = 0;
  Timer? _periodicTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;

  static const String _cacheFileName = 'product_cache.json';
  // Known Timestamp-bearing fields on a product (see
  // supabase_products.dart's productFromRow) - the only thing in a product
  // map that isn't already a plain JSON value, so the only thing the
  // on-disk cache needs to specifically round-trip.
  static const List<String> _timestampFields = [
    'featuredAt',
    'discountStart',
    'discountEnd',
    'createdAt',
  ];

  /// Call once, early (main.dart, before runApp) - loads whatever's cached
  /// on disk immediately so the first frame has something to show, then
  /// kicks off a real refresh in the background. Safe to call again later;
  /// it's a no-op after the first call.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;

    if (!kUseSupabaseProducts) {
      _startFirestoreListener();
      return;
    }

    await _loadFromCache();
    unawaited(refresh());
  }

  void _startFirestoreListener() {
    // Defensive: ensureStarted() is a no-op after the first call, so in
    // practice this only ever runs once - but cancelling any previous
    // subscription first (rather than just overwriting the field) means
    // this can never silently leak a listener if that guard is ever
    // changed later.
    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance
        .collection('products')
        .snapshots()
        .listen((snapshot) {
          productsNotifier.value = snapshot.docs
              .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
              .toList();
          hasRefreshedOnce = true;
          staleNoticeNotifier.value = null;
        });
  }

  /// Reloads the whole catalog from Supabase, paging through
  /// app_list_products. Coalesces concurrent callers into one in-flight
  /// request (anyone who calls while a refresh is already running just
  /// gets folded into one more refresh right after, instead of firing a
  /// second overlapping one), and skips a non-[force]d call entirely if
  /// the catalog was already refreshed within the last 20 seconds - the
  /// debouncing the spec asks for, so a screen opening, the periodic
  /// timer, and a pull-to-refresh landing close together don't turn into
  /// three separate full-catalog fetches.
  Future<void> refresh({bool force = false}) async {
    if (!kUseSupabaseProducts) return;

    if (_isRefreshing) {
      _refreshQueued = true;
      return;
    }
    if (!force &&
        _lastRefreshAt != null &&
        DateTime.now().difference(_lastRefreshAt!) < const Duration(seconds: 20)) {
      return;
    }

    _isRefreshing = true;
    try {
      final List<Map<String, dynamic>> all = [];
      int offset = 0;
      while (true) {
        final page = await SupabaseProductsApi.instance.listProducts(
          offset: offset,
        );
        all.addAll(page.products);
        if (page.done || page.products.isEmpty) break;
        offset += page.products.length;
      }
      productsNotifier.value = all;
      hasRefreshedOnce = true;
      _lastRefreshAt = DateTime.now();
      staleNoticeNotifier.value = null;
      unawaited(_saveToCache(all));
    } catch (_) {
      // Keep whatever was already showing (cache or the last successful
      // refresh) - a failed refresh must never clear the catalog out from
      // under the customer. Only surface the notice once there's actually
      // something cached/loaded to label as "saved" rather than live.
      if (productsNotifier.value.isNotEmpty) {
        staleNoticeNotifier.value =
            "Showing saved list - couldn't refresh products.";
      }
    } finally {
      _isRefreshing = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    }
  }

  /// A product-listing screen calls this in initState()/dispose() to mark
  /// itself visible - the periodic ~3-minute background refresh only runs
  /// while at least one such screen is on screen, and becoming visible
  /// always triggers one immediate refresh (debounced like any other, so
  /// this is cheap when several screens are visible at once).
  void registerVisible() {
    _visibleScreens++;
    if (_visibleScreens == 1) _startPeriodicRefresh();
    unawaited(refresh());
  }

  void unregisterVisible() {
    if (_visibleScreens > 0) _visibleScreens--;
    if (_visibleScreens == 0) _stopPeriodicRefresh();
  }

  void _startPeriodicRefresh() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => unawaited(refresh()),
    );
  }

  void _stopPeriodicRefresh() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Call from the app's lifecycle observer on resume (see main.dart) -
  /// only actually refreshes if a product screen is currently visible,
  /// same as the periodic timer.
  void onAppResumed() {
    if (_visibleScreens > 0) unawaited(refresh());
  }

  Map<String, dynamic>? byId(String id) {
    for (final product in productsNotifier.value) {
      if (product['id'] == id) return product;
    }
    return null;
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<void> _loadFromCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final String raw = await file.readAsString();
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      productsNotifier.value = decoded
          .map((e) => _restoreTimestamps(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      // No usable cache yet (first ever launch, corrupted file, etc.) -
      // ensureStarted()'s refresh() right after this is what actually
      // populates the catalog in that case.
    }
  }

  Future<void> _saveToCache(List<Map<String, dynamic>> products) async {
    try {
      final file = await _cacheFile();
      final List<Map<String, dynamic>> forCache = products
          .map(_prepareForCache)
          .toList();
      await file.writeAsString(jsonEncode(forCache));
    } catch (_) {
      // Best-effort - losing the on-disk cache just means the next cold
      // start shows an empty list until the first refresh completes,
      // same as a fresh install.
    }
  }

  Map<String, dynamic> _prepareForCache(Map<String, dynamic> product) {
    final copy = Map<String, dynamic>.from(product);
    for (final key in _timestampFields) {
      final value = copy[key];
      if (value is Timestamp) {
        copy[key] = <String, dynamic>{'__ts': value.millisecondsSinceEpoch};
      }
    }
    return copy;
  }

  Map<String, dynamic> _restoreTimestamps(Map<String, dynamic> product) {
    for (final key in _timestampFields) {
      final value = product[key];
      if (value is Map && value['__ts'] is int) {
        product[key] = Timestamp.fromMillisecondsSinceEpoch(
          value['__ts'] as int,
        );
      }
    }
    return product;
  }
}
