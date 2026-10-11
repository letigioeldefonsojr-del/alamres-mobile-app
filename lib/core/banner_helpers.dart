import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

Stream<DocumentSnapshot<Map<String, dynamic>>> storeBannerStream() {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('storeBanner')
      .snapshots();
}

Future<void> saveStoreBanner({
  required String offer,
  required String description,
  String? imageUrl,
  DateTime? scheduleStart,
  DateTime? scheduleEnd,
}) async {
  await FirebaseFirestore.instance
      .collection('settings')
      .doc('storeBanner')
      .set({
        'offer': offer,
        'description': description,
        'imageUrl': imageUrl,
        'scheduleStart': scheduleStart != null
            ? Timestamp.fromDate(scheduleStart)
            : null,
        'scheduleEnd': scheduleEnd != null
            ? Timestamp.fromDate(scheduleEnd)
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

bool isBannerCurrentlyValid(Map<String, dynamic> data) {
  final scheduleStart = data['scheduleStart'];
  final scheduleEnd = data['scheduleEnd'];
  final now = DateTime.now();
  if (scheduleStart is Timestamp && now.isBefore(scheduleStart.toDate())) {
    return false;
  }
  if (scheduleEnd is Timestamp && now.isAfter(scheduleEnd.toDate())) {
    return false;
  }
  return true;
}

Future<void> deleteStoreBanner() async {
  await FirebaseFirestore.instance
      .collection('settings')
      .doc('storeBanner')
      .delete();
}

/// A single slide in the home-screen promo carousel. Mirrors the same
/// shape the legacy single `settings/storeBanner` document always had
/// (`offer`, `description`, `imageUrl`, `scheduleStart`, `scheduleEnd`),
/// plus an `id` (the Firestore doc id, or `'legacy'` for the old single
/// document when it's used as a fallback) and an optional `sortOrder` so
/// admins can control carousel order explicitly instead of relying on
/// whatever order Firestore happens to return docs in.
class PromoBanner {
  final String id;
  final String offer;
  final String description;
  final String? imageUrl;
  final DateTime? scheduleStart;
  final DateTime? scheduleEnd;
  final int sortOrder;

  const PromoBanner({
    required this.id,
    required this.offer,
    required this.description,
    this.imageUrl,
    this.scheduleStart,
    this.scheduleEnd,
    this.sortOrder = 0,
  });

  factory PromoBanner.fromMap(String id, Map<String, dynamic> data) {
    final scheduleStart = data['scheduleStart'];
    final scheduleEnd = data['scheduleEnd'];
    return PromoBanner(
      id: id,
      offer: data['offer'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      scheduleStart: scheduleStart is Timestamp
          ? scheduleStart.toDate()
          : null,
      scheduleEnd: scheduleEnd is Timestamp ? scheduleEnd.toDate() : null,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  /// Same live-window rule as [isBannerCurrentlyValid], just as an
  /// instance getter so carousel code can filter a `List<PromoBanner>`
  /// with `.where((b) => b.isCurrentlyLive)` instead of re-unwrapping
  /// Firestore fields by hand.
  bool get isCurrentlyLive {
    final now = DateTime.now();
    if (scheduleStart != null && now.isBefore(scheduleStart!)) return false;
    if (scheduleEnd != null && now.isAfter(scheduleEnd!)) return false;
    return true;
  }
}

/// All promo banners from the new `storeBanners` collection, sorted by
/// `sortOrder` (ties keep Firestore's own doc order). Does NOT filter by
/// live window here - callers (the carousel) re-check that on a timer so
/// a banner whose schedule starts/ends while the app is already open
/// appears/disappears without needing a new Firestore write.
Stream<List<PromoBanner>> storeBannersStream() {
  return FirebaseFirestore.instance.collection('storeBanners').snapshots().map(
    (snapshot) {
      final banners = snapshot.docs
          .map((doc) => PromoBanner.fromMap(doc.id, doc.data()))
          .toList();
      banners.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return banners;
    },
  );
}
