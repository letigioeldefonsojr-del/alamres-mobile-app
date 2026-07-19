import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Handles OneSignal setup and linking a device to the signed-in
/// Firebase user so pushes can be targeted at them by uid.
class OneSignalService {
  OneSignalService._();
  static final OneSignalService instance = OneSignalService._();

  bool _initialized = false;

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

  /// Call right after a successful login (customer or employee),
  /// using the Firebase Auth uid. This is what lets you target
  /// this specific person later via the REST API.
  Future<void> login(String firebaseUid) async {
    await OneSignal.login(firebaseUid);
  }

  /// Call on logout so this device stops being associated with
  /// the account that just signed out.
  Future<void> logout() async {
    await OneSignal.logout();
  }
}
