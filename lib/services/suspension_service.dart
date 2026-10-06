import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared logic for checking whether a customer's account has been
/// suspended from the web admin panel. Staff write a `suspendedUntil`
/// Timestamp (and optionally a `suspensionReason` string) onto
/// users/{uid} when they suspend someone; no `suspendedUntil` field (or
/// one whose date has already passed) means the account isn't suspended.
///
/// Used both at login (login_screen.dart, a one-off fetch) and
/// continuously while the app is running (suspension_watcher.dart, which
/// gets pushed already-fetched document data from a live `.snapshots()`
/// listener instead of fetching itself) - both need the exact same
/// "is this account currently suspended" logic, so it lives here once
/// instead of being duplicated. Both also feed the result straight into
/// SuspendedAccountOverlay (see widgets/suspended_account_overlay.dart),
/// which is why this returns the reason/date as their own fields rather
/// than one pre-formatted message string.
class SuspensionCheckResult {
  final bool isSuspended;
  final String? reason;
  final DateTime? suspendedUntil;
  const SuspensionCheckResult({
    required this.isSuspended,
    this.reason,
    this.suspendedUntil,
  });
}

/// Pure evaluation of already-fetched user-document data - no Firestore
/// call of its own. This is what the live listener in
/// suspension_watcher.dart calls on every snapshot, since it already has
/// the document data handed to it.
SuspensionCheckResult evaluateSuspension(Map<String, dynamic>? data) {
  final Timestamp? suspendedUntil = data?['suspendedUntil'] as Timestamp?;

  if (suspendedUntil != null && suspendedUntil.toDate().isAfter(DateTime.now())) {
    final String? reason = data?['suspensionReason'] as String?;
    return SuspensionCheckResult(
      isSuspended: true,
      // Treat a blank string the same as "no reason set" so the overlay
      // can just check for null rather than also checking for empty.
      reason: (reason != null && reason.trim().isNotEmpty) ? reason : null,
      suspendedUntil: suspendedUntil.toDate(),
    );
  }
  return const SuspensionCheckResult(isSuspended: false);
}

/// One-off check that fetches users/{uid} itself, then runs it through
/// [evaluateSuspension]. Used where there's no live listener yet to hand
/// off already-fetched data, e.g. the check login_screen.dart runs
/// immediately after a customer signs in.
Future<SuspensionCheckResult> checkAccountSuspension(String uid) async {
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();
  return evaluateSuspension(doc.data());
}

// Month names spelled out here rather than pulling in the intl package
// just to format one date. Used by SuspendedAccountOverlay to render
// the "Suspended until" line.
const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String formatSuspensionDate(DateTime date) {
  final String month = _monthNames[date.month - 1];
  final int hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final String minute = date.minute.toString().padLeft(2, '0');
  final String period = date.hour >= 12 ? 'PM' : 'AM';
  return '$month ${date.day}, ${date.year} at $hour12:$minute $period';
}
