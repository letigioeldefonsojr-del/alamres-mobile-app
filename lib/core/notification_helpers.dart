import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/onesignal_push_sender.dart';

Future<void> addCustomerNotification({
  required String userId,
  required String message,
  String? orderId,
}) async {
  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .get();
  final prefs = userDoc.data()?['notificationPrefs'] as Map<String, dynamic>?;
  final bool orderUpdatesEnabled = (prefs?['orderUpdates'] as bool?) ?? true;
  if (!orderUpdatesEnabled) return;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('notifications')
      .add({
        'message': message,
        'orderId': orderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
}

Future<void> notifyCustomerOrderUpdate({
  required String userId,
  required String message,
  String? orderId,
}) async {
  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .get();
  final prefs = userDoc.data()?['notificationPrefs'] as Map<String, dynamic>?;
  final bool orderUpdatesEnabled = (prefs?['orderUpdates'] as bool?) ?? true;

  await addCustomerNotification(
    userId: userId,
    message: message,
    orderId: orderId,
  );

  if (orderUpdatesEnabled) {
    await sendPushNotification(
      toFirebaseUid: userId,
      message: message,
      orderId: orderId,
    );
  }
}
