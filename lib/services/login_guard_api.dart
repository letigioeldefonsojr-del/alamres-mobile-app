import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Thrown by [LoginGuardApi] when the function itself answers with
/// {"error":"slow_down"} (HTTP 429) - too many lookups too quickly. Callers
/// that show the customer something should show exactly "Too many attempts,
/// please wait a moment and try again." for this; any other failure (a
/// non-200 response, an unreadable body, a network error) should fall back
/// to whatever generic error message that screen already shows.
class LoginGuardRateLimitException implements Exception {
  const LoginGuardRateLimitException();
}

/// The only place this app talks to the `login-guard` Supabase Edge
/// Function - the pre-sign-in counterpart to SupabaseProductsApi (see
/// supabase_products.dart). Firestore's `users` collection is no longer
/// publicly readable (security rules now only let a signed-in customer
/// read their own `users/{uid}` document), so the handful of lookups this
/// app used to run against it *before* a customer is signed in - turning a
/// typed mobile number into a sign-in email at login, checking whether a
/// mobile number/email is already registered at sign-up - go through this
/// instead. No Firebase ID token is sent (there isn't a signed-in customer
/// yet at this point); the publishable key alone is enough for the function
/// to answer these two narrow questions.
class LoginGuardApi {
  LoginGuardApi._();
  static final LoginGuardApi instance = LoginGuardApi._();

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final http.Response response = await http
        .post(
          Uri.parse(kSupabaseLoginGuardUrl),
          headers: {
            'Content-Type': 'application/json',
            'apikey': kSupabasePublishableKey,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    Map<String, dynamic>? decoded;
    try {
      final dynamic parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      // Leave decoded null - handled as a generic failure below, same as a
      // response body that doesn't even parse as JSON.
    }

    final String? error = decoded?['error'] as String?;
    if (response.statusCode == 429 || error == 'slow_down') {
      throw const LoginGuardRateLimitException();
    }
    if (response.statusCode != 200 || decoded == null || error != null) {
      throw Exception('login_guard_failed: ${error ?? response.statusCode}');
    }
    return decoded;
  }

  /// Resolves a mobile number - as typed, the function accepts 0917...,
  /// 63917..., 917... and +63917... alike - to the matching account's
  /// sign-in email, for the mobile-number branch of login. Returns null if
  /// no account matches (caller shows the existing "no account found"
  /// message for that, same as before).
  Future<String?> resolveMobileToEmail(String mobile) async {
    final data = await _call({'action': 'customer_resolve', 'mobile': mobile});
    if (data['found'] != true) return null;
    return data['email'] as String?;
  }

  /// Checks whether an email and/or mobile number is already registered -
  /// pass only whichever field the caller actually needs checked.
  Future<({bool emailTaken, bool mobileTaken})> checkTaken({
    String? email,
    String? mobile,
  }) async {
    final data = await _call({
      'action': 'customer_taken',
      if (email != null) 'email': email,
      if (mobile != null) 'mobile': mobile,
    });
    return (
      emailTaken: data['emailTaken'] == true,
      mobileTaken: data['mobileTaken'] == true,
    );
  }
}
