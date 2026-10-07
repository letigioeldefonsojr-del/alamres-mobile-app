import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../core/routing.dart';
import '../screens/customer/home_screen.dart';

/// Handles OneSignal setup and linking a device to the signed-in
/// Firebase user so pushes can be targeted at them by uid.
class OneSignalService {
  OneSignalService._();
  static final OneSignalService instance = OneSignalService._();

  bool _initialized = false;
  bool _clickListenerRegistered = false;

  /// Call once, early in main(), before runApp().
  /// [appId] is your OneSignal App ID from the OneSignal dashboard
  /// (Settings → Keys & IDs).
  Future<void> init(String appId) async {
    if (_initialized) return;
    _initialized = true;

    // Optional: helpful while testing, remove for production.
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

    OneSignal.initialize(appId);

    // Prompts the OS notification permission dialog.
    await OneSignal.Notifications.requestPermission(true);
  }

  /// Call once, early in main() right after init() - routes a tap on any
  /// push notification to the right tab instead of just opening whatever
  /// screen the app happened to launch on. An order-update push (see
  /// onesignal_push_sender.dart - it always carries an `orderId`) goes to
  /// Orders; anything else - a promotion push with no orderId - just opens
  /// the app on Home. Works whether the app was already open or the tap is
  /// what's launching it from a cold start.
  void setupNotificationClickHandling(GlobalKey<NavigatorState> navigatorKey) {
    if (_clickListenerRegistered) return;
    _clickListenerRegistered = true;

    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      final String? orderId = data?['orderId'] as String?;
      final bool isOrderPush = orderId != null && orderId.trim().isNotEmpty;
      _handleClick(navigatorKey, isOrderPush ? 2 : 0);
    });
  }

  Future<void> _handleClick(
    GlobalKey<NavigatorState> navigatorKey,
    int tabIndex,
  ) async {
    // Nothing to show an order/home screen for if nobody's signed in - let
    // the app's normal splash/login flow run its course instead of forcing
    // a screen that assumes a logged-in customer.
    if (FirebaseAuth.instance.currentUser == null) return;

    // If this tap is what's launching the app from a cold start, the
    // Navigator may not be mounted the instant the click event arrives -
    // wait briefly instead of silently dropping the tap.
    NavigatorState? navState = navigatorKey.currentState;
    int attempts = 0;
    while (navState == null && attempts < 25) {
      await Future.delayed(const Duration(milliseconds: 200));
      navState = navigatorKey.currentState;
      attempts++;
    }
    if (navState == null) return;

    // Clears back to a fresh HomeScreen on the target tab rather than
    // pushing on top of whatever's there - same pattern SuspensionWatcher
    // uses for its own navigatorKey-driven redirects. SplashScreen already
    // guards its own delayed redirect with `if (!mounted) return;`, so if
    // this fires while splash is still showing, splash's own redirect
    // simply no-ops once its route has been removed from the stack.
    navState.pushAndRemoveUntil(
      fadeSlideRoute(HomeScreen(initialTabIndex: tabIndex)),
      (route) => false,
    );
  }

  /// Call right after a successful login (customer or employee),
  /// using the Firebase Auth uid. This is what lets you target
  /// this specific person later via the REST API.
  Future<void> login(String firebaseUid) async {
    await OneSignal.login(firebaseUid);
    // Keep OneSignal's own copy of this device's promotions preference in
    // sync right as the device gets linked to this account - this is what
    // lets a promo push be targeted by a plain OneSignal tag filter
    // (promotions_enabled = true) instead of the sender having to look
    // every customer's preference up in Firestore one by one.
    unawaited(_syncPromotionsTag());
  }

  /// Call on logout so this device stops being associated with
  /// the account that just signed out.
  Future<void> logout() async {
    await OneSignal.logout();
  }

  Future<void> _syncPromotionsTag() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final prefs = doc.data()?['notificationPrefs'] as Map<String, dynamic>?;
      final bool enabled = (prefs?['promotions'] as bool?) ?? true;
      await setPromotionsTag(enabled);
    } catch (_) {
      // Non-critical - worst case the tag is briefly stale until the next
      // login or the next time the preference is changed in-app.
    }
  }

  /// Call right after the "Promotions & Offers" toggle is saved in
  /// Notifications settings, so the OneSignal tag reflects the new choice
  /// immediately instead of waiting for the next login.
  Future<void> setPromotionsTag(bool enabled) async {
    try {
      await OneSignal.User.addTagWithKey(
        'promotions_enabled',
        enabled ? 'true' : 'false',
      );
    } catch (_) {
      // Non-critical - the preference is still saved in Firestore either
      // way; only the admin-side push targeting would miss this update.
    }
  }
}
