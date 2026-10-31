import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/banner_helpers.dart';

/// Everything [PromoBannerCarousel] needs to decide what to show: the raw
/// `storeBanners` collection (already sorted by `sortOrder`, NOT filtered
/// to only-currently-live - the carousel does that itself against "now")
/// and the raw legacy `settings/storeBanner` document, exactly as they
/// came back from Firestore.
class BannerSnapshot {
  final List<PromoBanner> newBanners;
  final Map<String, dynamic>? legacyData;
  const BannerSnapshot({this.newBanners = const [], this.legacyData});
}

/// In-memory, 5-minute cache for the home-screen promo banner data.
///
/// Before this existed, [PromoBannerCarousel] kept a `storeBanners`
/// collection listener and a legacy `settings/storeBanner` document
/// listener open for as long as the home screen was alive - and Firestore
/// bills a snapshot listener for an initial read the moment it attaches,
/// so simply navigating away from Home and back re-opened both listeners
/// and paid for both reads all over again, on top of whatever either
/// stream pushed while open. The carousel now calls [ensureFresh] once
/// when it first builds (or when 5 minutes have passed), and its own 60s
/// schedule-window recheck timer - which only needs to re-evaluate which
/// banners count as "currently live" against the clock, not re-read the
/// documents - reads [cachedSnapshot] instead, which never touches
/// Firestore.
class BannerRepository {
  BannerRepository._();
  static final BannerRepository instance = BannerRepository._();

  static const Duration _ttl = Duration(minutes: 5);

  BannerSnapshot _snapshot = const BannerSnapshot();
  DateTime? _fetchedAt;
  Future<BannerSnapshot>? _inFlightFetch;

  bool get _isFresh =>
      _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < _ttl;

  /// Whatever was last fetched - possibly several minutes stale, possibly
  /// never fetched at all (empty) - without hitting Firestore. Safe to
  /// call as often as the carousel's 60s recheck timer likes.
  BannerSnapshot get cachedSnapshot => _snapshot;

  /// Returns fresh banner data - from the cache when it's under 5 minutes
  /// old, otherwise via one real `.get()` against each source.
  /// Concurrent callers that land while a fetch is already in flight
  /// share that same fetch rather than firing a second one (same pattern
  /// as `CustomerProfileCache.getProfile`).
  Future<BannerSnapshot> ensureFresh() async {
    if (_isFresh) return _snapshot;
    if (_inFlightFetch != null) return _inFlightFetch!;

    final future = _fetch();
    _inFlightFetch = future;
    try {
      return await future;
    } finally {
      _inFlightFetch = null;
    }
  }

  Future<BannerSnapshot> _fetch() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('storeBanners').get(),
        FirebaseFirestore.instance
            .collection('settings')
            .doc('storeBanner')
            .get(),
      ]);
      final newBannersSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final legacyDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

      final banners = newBannersSnap.docs
          .map((doc) => PromoBanner.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      _snapshot = BannerSnapshot(
        newBanners: banners,
        legacyData: legacyDoc.data(),
      );
      _fetchedAt = DateTime.now();
      return _snapshot;
    } catch (_) {
      // Keep whatever was cached before rather than let a failed refresh
      // wipe out a banner the carousel is already showing.
      return _snapshot;
    }
  }
}
