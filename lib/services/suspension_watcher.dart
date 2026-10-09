import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'onesignal_service.dart';
import 'suspension_service.dart';
import '../core/routing.dart';
import '../screens/customer/login_screen.dart';

/// Wraps the whole app (mounted once via MaterialApp's `builder`, so it
/// survives every screen navigation) and watches, in real time, for the
/// signed-in customer's account being suspended from the web admin panel.
///
/// Rather than polling on a timer, this keeps a live Firestore
/// `.snapshots()` listener open on the signed-in customer's own
/// users/{uid} document for as long as they're signed in. The moment
/// staff write a `suspendedUntil` onto that document from the admin
/// panel, Firestore pushes the updated document straight down this
/// listener - no delay waiting on a timer or an app-resume event.
///
/// The doc listener is started and stopped by following
/// FirebaseAuth's own authStateChanges() stream, which is what makes
/// "start right after login succeeds" and "stop on manual logout" both
/// automatic - authStateChanges fires immediately after any sign-in
/// (email/password, Google, or the auto sign-in from a kept session) and
/// again after any sign-out (the profile screen's Log Out button,
/// account deletion, or this very watcher's own forced sign-out), no
/// matter which screen triggered it. That's one listener to manage
/// instead of having to start/stop it from every login and logout call
/// site individually.
class SuspensionWatcher extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SuspensionWatcher({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<SuspensionWatcher> createState() => _SuspensionWatcherState();
}

class _SuspensionWatcherState extends State<SuspensionWatcher> {
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _suspensionSubscription;
  String? _watchedUid;
  bool _isHandlingSuspension = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthStateChanged,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _suspensionSubscription?.cancel();
    super.dispose();
  }

  void _onAuthStateChanged(User? user) {
    if (user == null) {
      _stopWatching();
      return;
    }
    // Already watching this exact account - nothing to do (avoids
    // tearing down and re-subscribing on every unrelated auth stream
    // event for the same signed-in user).
    if (user.uid == _watchedUid) return;
    _startWatching(user.uid);
  }

  void _startWatching(String uid) {
    _suspensionSubscription?.cancel();
    _watchedUid = uid;
    _suspensionSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(_handleSnapshot, onError: (_) {});
  }

  void _stopWatching() {
    _suspensionSubscription?.cancel();
    _suspensionSubscription = null;
    _watchedUid = null;
  }

  Future<void> _handleSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (_isHandlingSuspension) return;

    // The very first snapshot after (re)subscribing can be served
    // straight from Firestore's local cache before it's reconciled with
    // the server - if that cache still remembers this account as
    // suspended from before a lift, acting on it here would bounce a
    // customer who was just let back in straight back out again, with
    // no visible error (it just looks like their tap "didn't work").
    // Skip cache-sourced snapshots and only act on server-confirmed
    // ones; the confirmed snapshot arrives moments later on this same
    // listener, so real-time suspension still takes effect instantly -
    // it just doesn't act on a snapshot it can't yet trust.
    if (snapshot.metadata.isFromCache) return;

    final result = evaluateSuspension(snapshot.data());
    if (!result.isSuspended) return;

    _isHandlingSuspension = true;
    // Stop watching before signing out - signOut() will itself trigger
    // authStateChanges(user: null), which would otherwise race with this
    // same teardown.
    _stopWatching();

    // Detach this device from the account being forced out, same as any
    // other sign-out - a suspended, kicked-out account shouldn't keep
    // getting targeted pushes on this device.
    unawaited(
      OneSignalService.instance.logout().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      ),
    );

    // This is a forced sign-out - make sure splash_screen.dart's "keep me
    // logged in" fallbacks (Google session / saved email+password) can't
    // silently sign this suspended account back in on the next cold start.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('keepLoggedIn', false);
    } catch (_) {}
    try {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.delete(key: 'savedLoginEmail');
      await secureStorage.delete(key: 'savedLoginPassword');
    } catch (_) {}

    await FirebaseAuth.instance.signOut();

    final navState = widget.navigatorKey.currentState;
    if (navState != null) {
      // LoginScreen shows the glass suspended-account overlay itself as
      // soon as it appears, whenever suspendedUntil is passed in - see
      // its initState.
      navState.pushAndRemoveUntil(
        fadeSlideRoute(
          LoginScreen(
            suspendedReason: result.reason,
            suspendedUntil: result.suspendedUntil,
          ),
        ),
        (route) => false,
      );
    }

    _isHandlingSuspension = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
