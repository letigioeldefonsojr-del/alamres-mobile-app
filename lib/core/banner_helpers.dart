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
