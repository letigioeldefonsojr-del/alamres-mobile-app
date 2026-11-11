// auth-persistence
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Shared "keep me logged in" bookkeeping, written after any sign-in OR
// sign-up that lands the customer straight in the app. splash_screen.dart
// reads these same keys on every cold start to decide whether/how to
// silently restore a session - login_screen.dart was the only place
// writing them, so a customer who REGISTERS (register_screen.dart signs
// the new account straight in, same as a login) and then has Android kill
// the app from the recent-apps list - Firebase Auth's own persisted
// session doesn't reliably survive that on several OEM builds - had
// nothing for that fallback to use and landed back on the Login screen.
const String kKeepLoggedInPrefsKey = 'keepLoggedIn';
const String kLastSignInWasGooglePrefsKey = 'lastSignInWasGoogle';
const String kSavedLoginEmailKey = 'savedLoginEmail';
const String kSavedLoginPasswordKey = 'savedLoginPassword';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

/// Call right after any successful sign-in or sign-up (email/password or
/// Google) that lands the customer straight in the app. [keepLoggedIn]
/// defaults to true to match this app's own default ("Keep me logged in"
/// starts checked on the Login screen, and there's no such checkbox on
/// Register at all, so a brand-new account is always treated as keeping
/// the customer logged in).
Future<void> saveLoginPersistence({
  required bool isGoogle,
  bool keepLoggedIn = true,
  String? email,
  String? password,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kKeepLoggedInPrefsKey, keepLoggedIn);
    await prefs.setBool(kLastSignInWasGooglePrefsKey, isGoogle);
  } catch (_) {
    // Non-critical - worst case the app just defaults to staying signed in
    // on the next cold start.
  }

  try {
    if (!isGoogle && keepLoggedIn && email != null && password != null) {
      await _secureStorage.write(key: kSavedLoginEmailKey, value: email);
      await _secureStorage.write(key: kSavedLoginPasswordKey, value: password);
    } else {
      // Google sign-in/up, or "keep me logged in" unchecked - nothing for
      // the email/password fallback to use, so make sure nothing stale is
      // left behind from an earlier login.
      await _secureStorage.delete(key: kSavedLoginEmailKey);
      await _secureStorage.delete(key: kSavedLoginPasswordKey);
    }
  } catch (_) {
    // Non-critical - worst case the email/password fallback just can't run
    // on the next cold start.
  }
}
