import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/routing.dart';
import '../services/onesignal_service.dart';
import 'customer/home_screen.dart';
import 'customer/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);
  // Keys must match the ones login_screen.dart writes to.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _savedEmailKey = 'savedLoginEmail';
  static const String _savedPasswordKey = 'savedLoginPassword';

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;

      // Read from authStateChanges() instead of the synchronous
      // currentUser getter. Right at a cold app start - especially right
      // after the OS has killed and fully evicted the process, which is
      // exactly when "keep me logged in" needs to work - Firebase Auth's
      // native layer can still be in the middle of restoring the
      // previously-persisted session from disk. currentUser reads
      // whatever's in memory *right now*, so it can come back null for a
      // brief moment even though a real session is on disk and about to
      // be restored a beat later. authStateChanges() is guaranteed by
      // Firebase to only fire its first event once that restoration has
      // actually resolved (to the restored user, or to a confirmed null
      // if there genuinely isn't a session) - awaiting it instead removes
      // this race entirely rather than hoping a fixed delay was long
      // enough on every device.
      var user = await FirebaseAuth.instance.authStateChanges().first;

      // Read both preferences up front - "keep me logged in" is needed
      // whether or not Firebase handed back a user (to decide whether an
      // already-restored user should be signed back out, or whether it's
      // worth attempting the Google fallback below when Firebase's own
      // session comes back empty). Defaults to staying signed in if never
      // set (e.g. very first launch).
      bool keepLoggedIn = true;
      bool lastSignInWasGoogle = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        keepLoggedIn = prefs.getBool('keepLoggedIn') ?? true;
        lastSignInWasGoogle = prefs.getBool('lastSignInWasGoogle') ?? false;
      } catch (_) {
        // Non-critical - fall back to staying signed in.
      }

      if (user != null) {
        // "Keep me logged in" was unchecked at login - honor that on this
        // fresh app launch by signing back out instead of dropping the
        // customer straight into HomeScreen.
        if (!keepLoggedIn) {
          // Same reasoning as manually logging out from the profile
          // screen - detach this device from the account before signing
          // it out, so a shared/reused device doesn't keep receiving
          // pushes meant for the account that just got signed out here.
          unawaited(
            OneSignalService.instance.logout().timeout(
              const Duration(seconds: 5),
              onTimeout: () {},
            ),
          );
          await FirebaseAuth.instance.signOut();
          user = null;
        }
      } else if (keepLoggedIn && lastSignInWasGoogle) {
        // Firebase Auth's own persisted session came back empty even
        // though nothing in this app signed the customer out - on some
        // devices (certain OEM Android builds in particular) that session
        // does not reliably survive the app being killed from the
        // recent-apps list. Google Sign-In keeps its own session in
        // Android's system-level account manager (via Google Play
        // Services), a separate storage layer from this app's own, so it
        // tends to survive even when Firebase's app-local session
        // doesn't. Only attempted when the customer's last successful
        // login here was through Google and they had "keep me logged in"
        // checked; entirely silent, and any failure just falls through to
        // the normal "show Login screen" behavior below.
        try {
          final GoogleSignInAccount? googleUser = await GoogleSignIn()
              .signInSilently();
          if (googleUser != null) {
            final GoogleSignInAuthentication googleAuth =
                await googleUser.authentication;
            final oauthCredential = GoogleAuthProvider.credential(
              accessToken: googleAuth.accessToken,
              idToken: googleAuth.idToken,
            );
            final userCredential = await FirebaseAuth.instance
                .signInWithCredential(oauthCredential);
            user = userCredential.user;
          }
        } catch (_) {
          // No cached Google session, no network, Play Services
          // unavailable, etc. - never block startup on this, just fall
          // through to the normal Login screen below.
        }
      } else if (keepLoggedIn && !lastSignInWasGoogle) {
        // Same idea as the Google fallback above, but for an email/
        // password login. Firebase Auth has no separate outside-the-app
        // session layer for email/password the way Google Sign-In does,
        // so the only way to silently restore this kind of session on a
        // device where Firebase's own persisted session doesn't survive
        // is to keep the credentials themselves ready to replay - read
        // here from the device's hardware-backed secure storage (never
        // plain text), and only present at all when "keep me logged in"
        // was checked at the most recent email/password login. Cleared
        // immediately on manual logout, a forced sign-out, or switching
        // to Google login - see login_screen.dart, profile_tab.dart and
        // suspension_watcher.dart.
        try {
          final String? savedEmail = await _secureStorage.read(
            key: _savedEmailKey,
          );
          final String? savedPassword = await _secureStorage.read(
            key: _savedPasswordKey,
          );
          if (savedEmail != null && savedPassword != null) {
            final userCredential = await FirebaseAuth.instance
                .signInWithEmailAndPassword(
                  email: savedEmail,
                  password: savedPassword,
                );
            user = userCredential.user;
          }
        } catch (_) {
          // Wrong/changed password, no network, account disabled, etc. -
          // never block startup on this, just fall through to the normal
          // Login screen below.
        }
      }

      if (!mounted) return;

      // A push notification tap is already driving where this app lands -
      // e.g. straight into a specific order - so this screen's own plain
      // "go to Home tab 0 (or Login)" redirect must stay out of the way
      // entirely, rather than risk firing on top of (or right after) that
      // more specific redirect and undoing it.
      if (OneSignalService.instance.handledNotificationLaunch) return;

      if (user == null) {
        Navigator.pushReplacement(
          context,
          fadeSlideRoute(const LoginScreen()),
        );
        return;
      }

      Navigator.pushReplacement(context, fadeSlideRoute(const HomeScreen()));
    });
  }

  Widget _dot(bool active) {
    return Container(
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? 1 : 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 88,
                height: 88,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Almares 328',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'MOBILE ORDERING SYSTEM',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dot(false),
                  const SizedBox(width: 6),
                  _dot(true),
                  const SizedBox(width: 6),
                  _dot(false),
                ],
              ),
              const Spacer(flex: 4),
              Text(
                'Almares 328 — Your trusted sari-sari store, online.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
