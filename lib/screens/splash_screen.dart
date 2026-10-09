import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

      if (user != null) {
        // "Keep me logged in" was unchecked at login - honor that on this
        // fresh app launch by signing back out instead of dropping the
        // customer straight into HomeScreen. Defaults to staying signed in
        // if the preference was never set (e.g. very first launch).
        bool keepLoggedIn = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          keepLoggedIn = prefs.getBool('keepLoggedIn') ?? true;
        } catch (_) {
          // Non-critical - fall back to staying signed in.
        }
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
