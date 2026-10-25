import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Asks the Cloudflare Worker backend (see /cloudflare-worker at the
/// project root) to push a notification to one specific user via
/// OneSignal, targeting them by the Firebase uid you passed to
/// OneSignal.login().
///
/// The real OneSignal REST API key never lives in this app - it's a secret
/// that would let anyone who extracted it from the APK send a push
/// notification to your entire user base (compiling it in with
/// --dart-define, as this file used to, still ships it inside the release
/// APK in a recoverable form - a plain command-line flag was never the
/// actual problem, baking a secret into the client at all was). The Worker
/// holds that key as a Cloudflare secret and makes the real call to
/// OneSignal server-side; this app only ever talks to the Worker, and only
/// while the user is logged in (same pattern ChatService uses for the
/// Claude chat endpoint - see chat_service.dart). No --dart-define is
/// needed for this anymore, so a plain `flutter build apk --release` just
/// works.
Future<void> sendPushNotification({
  required String toFirebaseUid,
  required String message,
  String? orderId,
}) async {
  if (kChatWorkerUrl.isEmpty || kChatWorkerUrl == 'REPLACE_WITH_WORKER_URL') {
    // Mirrors ChatService's same guard - backend URL not set up yet.
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    final idToken = await user.getIdToken();

    final response = await http
        .post(
          Uri.parse('$kChatWorkerUrl/send-push'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'toFirebaseUid': toFirebaseUid,
            'message': message,
            'orderId': orderId ?? '',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      // ignore: avoid_print
      print(
        'Push notification failed (${response.statusCode}): ${response.body}',
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Push notification error: $e');
  }
}
