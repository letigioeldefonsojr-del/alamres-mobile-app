import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/suspension_service.dart';

/// Frosted-glass "account suspended" card, shown as a modal overlay in
/// two places: login_screen.dart when a customer tries to log in while
/// already suspended, and suspension_watcher.dart when the real-time
/// listener signs a customer out mid-session. Call
/// [showSuspendedAccountOverlay] rather than building this directly.
class SuspendedAccountOverlay extends StatelessWidget {
  final String? reason;
  final DateTime? suspendedUntil;

  const SuspendedAccountOverlay({
    super.key,
    this.reason,
    this.suspendedUntil,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            decoration: BoxDecoration(
              // Dark-tinted glass rather than light - the text on this
              // card is white, so the frosted panel itself needs to be
              // dark enough for that to actually read.
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'This Account is Suspended',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 16),
                if (reason != null) ...[
                  _InfoLine(label: 'Reason', value: reason!),
                  const SizedBox(height: 8),
                ],
                if (suspendedUntil != null)
                  _InfoLine(
                    label: 'Suspended until',
                    value: formatSuspensionDate(suspendedUntil!),
                  ),
                const SizedBox(height: 18),
                const Text(
                  'Contact an administrator if you believe this is a mistake.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.white),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Okay',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13.5,
          color: Colors.white,
          height: 1.4,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

/// Shows [SuspendedAccountOverlay] as a non-dismissible-by-tapping-away
/// modal (the "Okay" button is the only way out) over a dimmed
/// background - the dialog barrier provides the dim, BackdropFilter
/// inside the card itself provides the blur.
Future<void> showSuspendedAccountOverlay(
  BuildContext context, {
  String? reason,
  DateTime? suspendedUntil,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) =>
        SuspendedAccountOverlay(reason: reason, suspendedUntil: suspendedUntil),
  );
}
