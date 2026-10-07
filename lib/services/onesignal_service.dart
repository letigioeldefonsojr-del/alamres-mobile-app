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
  String? _lastHandledNotificationId;

  // Set the moment a notification tap starts being handled, and never
  // cleared back to false afterward - SplashScreen checks this before its
  // own default redirect so the two don't race each other. Without this,
  // on a cold start where the tap is what's launching the app, splash's
  // own 3-second timer could still fire its plain "go to Home tab 0"
  // redirect right on top of (or right after) this service's own redirect
  // to Orders, undoing it - which looked like the order screen opening
  // and then immediately bouncing back to Home.
  bool _handledNotificationLaunch = false;
  bool get handledNotificationLaunch => _handledNotificationLaunch;

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
      // OneSignal can report the same tap more than once - e.g. once as
      // the notification that launched the app from cold, and again once
      // the SDK is fully set up - and a second firing would otherwise
      // re-run this whole redirect on top of the first one. Skip any
      // repeat of a notification id already handled this session.
      final String? notificationId = event.notification.notificationId;
      if (notificationId != null &&
          notificationId == _lastHandledNotificationId) {
        return;
      }
      _lastHandledNotificationId = notificationId;
      _handledNotificationLaunch = true;

      final data = event.notification.additionalData;
      final String? orderId = data?['orderId'] as String?;
      final bool isOrderPush = orderId != null && orderId.trim().isNotEmpty;
      _handleClick(
        navigatorKey,
        isOrderPush ? 2 : 0,
        isOrderPush ? orderId : null,
      );
    });
  }

  Future<void> _handleClick(
    GlobalKey<NavigatorState> navigatorKey,
    int tabIndex,
    String? orderId,
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
    // uses for its own navigatorKey-driven redirects. SplashScreen checks
    // handledNotificationLaunch (set above, before this async work even
    // starts) and skips its own default redirect entirely once a
    // notification tap is being handled, so the two never fight over
    // which screen ends up on top.
    //
    // Opening the specific order (when orderId is set) is handled by
    // HomeScreen itself, right after this frame - not as a second,
    // separately timed Navigator call from here. Issuing it as its own
    // call after an extra Firestore round-trip left a gap, after this
    // pushAndRemoveUntil completed but before that second push landed,
    // where the order screen could end up missing its intended target.
    navState.pushAndRemoveUntil(
      fadeSlideRoute(
        HomeScreen(initialTabIndex: tabIndex, openOrderId: orderId),
      ),
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
