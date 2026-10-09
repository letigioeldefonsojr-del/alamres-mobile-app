import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Periodic "come back and shop" reminder notifications - purely local,
/// scheduled entirely on-device via Android's own alarm system, so they
/// still fire even when the app is fully closed (not just backgrounded or
/// minimized). This is deliberately separate from OneSignal: it needs no
/// server, no admin-website involvement, and nothing to configure in any
/// dashboard - it's fully controlled by this app and the customer's own
/// toggle in Notifications settings.
///
/// Off by default (opt-in) - see notifications_screen.dart's "Shop
/// Reminders" toggle.
class EngagementReminderService {
  EngagementReminderService._();
  static final EngagementReminderService instance =
      EngagementReminderService._();

  static const String _channelKey = 'shop_reminders';
  // Reserved notification-id range for these reminders specifically, so
  // cancelling/rescheduling this batch never touches any other kind of
  // notification this app might show in the future.
  static const int _idBase = 90000;

  // How far apart each reminder is, and how many to queue up at once.
  // 28 reminders at 6 hours apart covers a full week - comfortably more
  // than the typical gap between a customer opening the app, which is
  // when this queue gets refreshed (see applyPreference below), so in
  // practice the queue rarely actually runs dry.
  static const int _intervalHours = 6;
  static const int _scheduledBatchSize = 28;

  // A small rotating pool rather than one fixed line, so a customer who
  // gets several of these over a week doesn't see the exact same text
  // every time.
  static const List<String> _messages = [
    'Checkout na! Tingnan ang aming mga bagong produkto 🛒',
    'Miss ka na namin! May bago sa Almares 328 🛍️',
    'Mag-order ka na, dumating na ang sariwang stock! 🥫',
    'Huwag kalimutan ang grocery mo this week! 🛒',
    'May paborito ka na ba? I-check ang aming mga alok ngayon! 🔥',
  ];

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Call once, early in main() (Android only - this plugin doesn't
  /// meaningfully support web).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();
    // Almares 328 is a Philippines-based store - hardcoding this avoids
    // pulling in a separate device-timezone-detection package just for
    // this one feature. A few hours of drift from a wrong timezone
    // wouldn't even be noticeable for a loosely-timed reminder like this,
    // but Manila is correct for essentially every real customer anyway.
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      // Tapping one of these just opens the app normally (same as tapping
      // the launcher icon) - it's a generic nudge, not a link to anything
      // specific, so there's nothing more to handle here.
      onDidReceiveNotificationResponse: (_) {},
    );
  }

  /// Call whenever the "Shop Reminders" preference is loaded or changed -
  /// e.g. every time the customer lands on Home, and right when the
  /// toggle itself is flipped. Always fully replaces whatever was
  /// previously queued rather than appending to it, so it's safe to call
  /// repeatedly and the queue never grows unbounded or goes stale against
  /// an old setting.
  Future<void> applyPreference(bool enabled) async {
    if (!_initialized) return;

    try {
      for (int i = 0; i < _scheduledBatchSize; i++) {
        await _plugin.cancel(_idBase + i);
      }
      if (!enabled) return;

      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
      for (int i = 0; i < _scheduledBatchSize; i++) {
        final tz.TZDateTime when = now.add(
          Duration(hours: _intervalHours * (i + 1)),
        );
        final String message = _messages[i % _messages.length];
        await _plugin.zonedSchedule(
          _idBase + i,
          'Almares 328',
          message,
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelKey,
              'Shop Reminders',
              channelDescription:
                  'Occasional reminders to check out Almares 328',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          // Required by this package version's zonedSchedule() (removed in
          // a later major version, but still required as of the
          // flutter_local_notifications 18.0.1 this project is pinned to).
          // absoluteTime is the standard choice - it's iOS-specific and
          // this feature only configures Android anyway, so it has no
          // real effect here, but the parameter itself is mandatory
          // regardless of platform.
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // Non-critical - worst case the customer just doesn't get reminders
      // until the next time this runs (e.g. the next time they open the
      // app), rather than the app breaking over it.
    }
  }
}
