import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sends a push notification to one specific user via OneSignal's REST API,
/// targeting them by the Firebase uid you passed to OneSignal.login().
///
/// SECURITY NOTE: the REST API key below is a secret — anyone who has it
/// could send pushes to your whole user base. Don't hard-code it directly
/// in this file if you plan to ever push this project to a public GitHub
/// repo. Instead, pass it in at build/run time:
///
///   flutter run --dart-define=ONESIGNAL_REST_API_KEY=your_key_here
///   flutter build apk --dart-define=ONESIGNAL_REST_API_KEY=your_key_here
///
/// and it gets read here automatically via String.fromEnvironment.
/// Add a matching entry to your IDE's run configuration if you use
/// VS Code / Android Studio, so you don't have to type it every time.

const String _oneSignalAppId = String.fromEnvironment('ONESIGNAL_APP_ID');
const String _oneSignalRestApiKey = String.fromEnvironment(
  'ONESIGNAL_REST_API_KEY',
);

Future<void> sendPushNotification({
  required String toFirebaseUid,
  required String message,
  String? orderId,
}) async {
  if (_oneSignalAppId.isEmpty || _oneSignalRestApiKey.isEmpty) {
    // Fails silently in dev if you forgot --dart-define, so the app
    // doesn't crash — but nothing gets sent. Check your run config.
    // ignore: avoid_print
    print(
      'OneSignal not configured: pass --dart-define=ONESIGNAL_APP_ID=... '
      'and --dart-define=ONESIGNAL_REST_API_KEY=...',
    );
    return;
  }

  final uri = Uri.parse('https://onesignal.com/api/v1/notifications');

  final body = {
    'app_id': _oneSignalAppId,
    'include_aliases': {
      'external_id': [toFirebaseUid],
    },
    'target_channel': 'push',
    'headings': {'en': 'Almares 328'},
    'contents': {'en': message},
    'data': {'orderId': orderId ?? ''},
  };

  try {
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Basic $_oneSignalRestApiKey',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      // ignore: avoid_print
      print('OneSignal push failed (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    // ignore: avoid_print
    print('OneSignal push error: $e');
  }
}
