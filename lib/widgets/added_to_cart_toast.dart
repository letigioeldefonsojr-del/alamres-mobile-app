import 'dart:async';
import 'package:flutter/material.dart';

// Deliberately generous fixed estimate of the Home/Categories/Orders tabs'
// combined bottom chrome - the tab bar, the "View Cart" bar (which is
// showing by definition whenever this toast appears, right after adding
// something), and the chat assistant's floating button sitting above all
// of that. A plain SnackBar tries to measure this exactly via the
// Scaffold and gets it wrong here (see showAddedToCartToast's own doc
// below for why), so this toast instead just reserves comfortably more
// than the tallest realistic combination of the three needs - a few extra
// px of gap above the View Cart bar is a much smaller problem than
// overlapping it. Device-specific safe-area/gesture-nav inset is added on
// top of this separately wherever it's used, same as kFabBottomClearance.
const double _kBottomChromeClearance = 220;

/// Shows a brief "Added to cart" confirmation, floating just above the
/// Home/Categories/Orders tabs' bottom chrome - deliberately NOT a
/// SnackBar.
///
/// A plain floating SnackBar anchors to the bottom of the Scaffold's own
/// body-viewport, which Flutter computes from the Scaffold's actual
/// bottomNavigationBar/FAB geometry - that should just work, but with the
/// "View Cart" bar, the chat assistant's floating button, and the tab bar
/// all stacked at the bottom here, that computed viewport bottom ends up
/// landing mid-screen rather than near the real bottom edge, so the
/// SnackBar overlapped whatever product content happened to be there
/// instead of floating cleanly above everything. This toast sidesteps
/// that entirely by positioning itself directly, using a deliberately
/// generous fixed clearance (_kBottomChromeClearance) instead of trying
/// to measure the Scaffold's chrome exactly.
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
    // Slides up from below, same direction a normal bottom SnackBar would
    // - this is a bottom toast now, just positioned to actually clear the
    // bottom chrome instead of guessing wrong about where it ends.
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    // Same visible duration as the SnackBars this replaces, minus the time
    // reserved for the reverse (slide-down/fade-out) animation, so the
    // total time on screen still lands right around 2 seconds.
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
      bottom: _kBottomChromeClearance + MediaQuery.of(context).padding.bottom,
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
