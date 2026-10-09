import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the temporary "Hey Beta Tester!" announcement banner's config
/// from Firestore (config/betaAnnouncement) and figures out whether it
/// should be shown right now - without re-nagging a tester who's already
/// dismissed the current version of it.
///
/// This whole feature is meant to be thrown away once beta testing wraps
/// up:
///   - To turn it off for everyone immediately, no app update needed, just
///     set `enabled: false` on the Firestore doc (or delete the doc).
///   - To remove it from the app entirely afterward, delete this file and
///     its two call sites in home_screen.dart (the import, the
///     _checkBetaAnnouncement() call, and the method itself) - nothing
///     else in the app depends on it.
class BetaAnnouncementService {
  BetaAnnouncementService._();
  static final BetaAnnouncementService instance =
      BetaAnnouncementService._();

  static const String _seenVersionPrefsKey = 'beta_announcement_seen_version';

  /// Live version of the same "should this show right now" check, as a
  /// stream that re-evaluates every time the Firestore doc changes - so a
  /// tester already inside the app sees the banner the moment staff flip
  /// `enabled` or bump `version`, with no need to close and reopen the
  /// app. HomeScreen owns the subscription (see its initState/dispose).
  /// Emits null whenever the banner should not (or no longer) be shown:
  /// not configured yet, turned off, or this device already dismissed
  /// this exact version.
  Stream<BetaAnnouncement?> watch() {
    return FirebaseFirestore.instance
        .collection('config')
        .doc('betaAnnouncement')
        .snapshots()
        .asyncMap((doc) async {
          try {
            final data = doc.data();
            if (data == null) return null;

            final bool enabled = (data['enabled'] as bool?) ?? false;
            if (!enabled) return null;

            final String message = (data['message'] as String?)?.trim() ?? '';
            if (message.isEmpty) return null;

            // Bump this on the Firestore doc whenever the message changes
            // and you want it to resurface for testers who already
            // dismissed an earlier version - otherwise it only shows once
            // per tester, ever.
            final int version = (data['version'] as num?)?.toInt() ?? 1;

            final prefs = await SharedPreferences.getInstance();
            final int seenVersion = prefs.getInt(_seenVersionPrefsKey) ?? 0;
            if (version <= seenVersion) return null;

            return BetaAnnouncement(message: message, version: version);
          } catch (_) {
            // Non-critical - worst case a tester just doesn't see the
            // banner, rather than the app breaking over it.
            return null;
          }
        });
  }

  /// Call once the tester dismisses the banner, so this exact version
  /// never shows again on this device.
  Future<void> markSeen(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seenVersionPrefsKey, version);
  }
}

class BetaAnnouncement {
  final String message;
  final int version;

  const BetaAnnouncement({required this.message, required this.version});
}
