import 'package:flutter/foundation.dart';

/// Debug-only Firestore read accounting.
///
/// Every `.get()` and `.snapshots()` call site in the app reports here,
/// right after it resolves (a one-time `.get()`) or on each event (a live
/// `.snapshots()` listener), via [ReadCounter.log]. Each call logs how
/// many documents that specific read/snapshot actually cost, plus a
/// running total for the whole app session, to the console as:
///
///   [reads] <name> +<docCount> (total: <runningTotal>)
///
/// Entirely compiled out of behavior in release builds - every method is
/// a no-op unless [kDebugMode] is true, so this adds no cost and changes
/// nothing outside of local testing. This was added to track down a read
/// amplification bug (several Firestore reads re-created on every widget
/// rebuild instead of once), not meant to ship as a permanent feature -
/// safe to delete this file and its call sites once that's no longer
/// being actively investigated.
class ReadCounter {
  ReadCounter._();

  static int _total = 0;

  /// Running total of documents read this app session (debug builds only;
  /// always 0 in release).
  static int get total => _total;

  /// Logs one read: [name] identifies the call site (e.g.
  /// "orders_tab:history", "cart_badge:cart"), [docCount] is how many
  /// documents that specific `.get()`/snapshot actually returned (use 1
  /// for a single-document read/snapshot, `snapshot.docs.length` for a
  /// query).
  static void log(String name, int docCount) {
    if (!kDebugMode) return;
    _total += docCount;
    debugPrint('[reads] $name +$docCount (total: $_total)');
  }

  /// Resets the running total back to 0. Call at the very top of a fresh
  /// debug session (see main.dart) so a hot restart during testing starts
  /// counting over from zero instead of carrying over a stale total from
  /// before the restart.
  static void reset() {
    if (!kDebugMode) return;
    _total = 0;
  }
}
