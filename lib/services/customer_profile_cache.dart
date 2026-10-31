import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// In-memory, 5-minute cache for the signed-in customer's own
/// `users/{uid}` document.
///
/// Before this existed, Home (mobile number/address/shop-reminders check),
/// the Profile tab (phone number + app-update check), Notifications
/// settings, and Edit Profile each ran their own independent `.get()`
/// against this exact same document - so just tapping through Profile ->
/// Notifications -> back -> Edit Profile cost 3-4 reads of one document
/// that hadn't changed at all. Every one of those screens now calls
/// [getProfile] instead, which only actually hits Firestore when nothing
/// is cached yet or the cache has gone stale (>5 minutes).
class CustomerProfileCache {
  CustomerProfileCache._();
  static final CustomerProfileCache instance = CustomerProfileCache._();

  static const Duration _ttl = Duration(minutes: 5);

  String? _cachedUid;
  Map<String, dynamic>? _cachedData;
  DateTime? _fetchedAt;
  Future<Map<String, dynamic>?>? _inFlightFetch;

  bool _isFreshFor(String uid) =>
      _cachedUid == uid &&
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) < _ttl;

  /// Returns the signed-in customer's own profile fields - from the cache
  /// when it's for this same [uid] and under 5 minutes old, otherwise via
  /// one real Firestore `.get()`. Concurrent callers that land while a
  /// fetch is already in flight share that same fetch rather than firing a
  /// second one.
  Future<Map<String, dynamic>?> getProfile({required String uid}) async {
    if (_isFreshFor(uid)) return _cachedData;
    if (_inFlightFetch != null) return _inFlightFetch;

    final Future<Map<String, dynamic>?> future = _fetch(uid);
    _inFlightFetch = future;
    try {
      return await future;
    } finally {
      _inFlightFetch = null;
    }
  }

  Future<Map<String, dynamic>?> _fetch(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      _cachedUid = uid;
      _cachedData = doc.data();
      _fetchedAt = DateTime.now();
      return _cachedData;
    } catch (_) {
      // Keep whatever was cached before (if anything) rather than let a
      // failed refresh wipe out data a screen already successfully showed.
      return _cachedUid == uid ? _cachedData : null;
    }
  }

  /// Call right after a successful write to this profile (Edit Profile's
  /// Save, Notifications' per-toggle save) with exactly the fields that
  /// changed - merges them straight into the cache and resets its age, so
  /// every other screen sees the update immediately without costing a
  /// second read. A no-op if nothing is cached yet for this [uid]; the next
  /// [getProfile] call will just fetch fresh.
  void updateCache(String uid, Map<String, dynamic> changedFields) {
    if (_cachedUid != uid || _cachedData == null) return;
    _cachedData = {..._cachedData!, ...changedFields};
    _fetchedAt = DateTime.now();
  }

  /// Call on logout/account deletion so a different account signing in
  /// right after on the same device never sees the previous customer's
  /// still-fresh cached profile.
  void clear() {
    _cachedUid = null;
    _cachedData = null;
    _fetchedAt = null;
  }
}
