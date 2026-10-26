import 'dart:async';
import 'package:flutter/material.dart';

/// Shows a brief "Added to cart" confirmation pinned near the TOP of the
/// screen - deliberately NOT a SnackBar.
///
/// On the Home/Categories/Orders tabs the bottom of the screen is already
/// busy with the chat assistant's floating button, the "View Cart" bar,
/// and the tab bar itself - a bottom-floating SnackBar has to squeeze into
/// whatever body height is left above all of that, which isn't much, so
/// it ends up overlapping whatever's at the bottom of the current scroll
/// position (a product's own price, right after adding it) instead of
/// floating cleanly above everything the way it's supposed to. Anchoring
/// this to the top instead guarantees it never competes with any of that
/// - there's nothing else fixed up there to collide with.
void showAddedToCartToast(BuildContext context, {String message = 'Added to cart'}) {
  showAddedToCartToastOnOverlay(
    Overlay.of(context, rootOverlay: true),
    message: message,
  );
}

/// Same as [showAddedToCartToast], but takes an already-resolved
/// [OverlayState] instead of looking one up from a BuildContext. Use this
/// when the context that would normally resolve the overlay won't still
/// be mounted by the time you're ready to show the toast - e.g.
/// product_options_sheet.dart captures its Overlay before popping itself
/// off the navigation stack, since its own context is gone the instant
/// after that pop.
void showAddedToCartToastOnOverlay(
  OverlayState overlay, {
  String message = 'Added to cart',
}) {
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AddedToCartToast(
      message: message,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _AddedToCartToast extends StatefulWidget {
  final String message;
  final VoidCallback onDone;

  const _AddedToCartToast({required this.message, required this.onDone});

  @override
  State<_AddedToCartToast> createState() => _AddedToCartToastState();
}

class _AddedToCartToastState extends State<_AddedToCartToast>
    with SingleTickerProviderStateMixin {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    // Same visible duration as the SnackBars this replaces, minus the time
    // reserved for the reverse (slide-up/fade-out) animation, so the total
    // time on screen still lands right around 2 seconds.
    _timer = Timer(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
