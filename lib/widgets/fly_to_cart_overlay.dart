import 'package:flutter/material.dart';
import '../core/cart_fly_anchor.dart';
import 'product_image.dart';

/// Plays the "shrinks and flies toward the cart" animation after a
/// successful Add to Cart - a small copy of the product image travels from
/// [startRect] (the real product image's on-screen position at the moment
/// Add to Cart was tapped) to wherever the cart icon currently is, then
/// fades out and removes itself. Purely a visual flourish - the cart
/// badge's own count already updates on its own once the Firestore write
/// behind the add completes, independent of this animation.
///
/// [overlay] must be the root overlay (`Overlay.of(context, rootOverlay:
/// true)`), captured by the caller *before* closing whatever sheet/dialog
/// triggered this, so the flight is never clipped by a route that's in the
/// middle of closing. [screenSize] and [topPadding] are only used for the
/// fallback target when no cart icon happens to be mounted right now.
void flyToCart(
  OverlayState overlay, {
  required String? imageUrl,
  required Rect startRect,
  required Size screenSize,
  required double topPadding,
}) {
  final renderObject = cartIconKey.currentContext?.findRenderObject();
  Rect targetRect;
  if (renderObject is RenderBox && renderObject.attached) {
    final Offset topLeft = renderObject.localToGlobal(Offset.zero);
    targetRect = topLeft & renderObject.size;
  } else {
    // No cart icon is currently on screen (e.g. this screen doesn't show
    // one) - aim for a generic top-right spot, roughly where one
    // conventionally lives, rather than skipping the animation entirely.
    targetRect = Rect.fromLTWH(screenSize.width - 54, topPadding + 10, 28, 28);
  }

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _FlyToCartImage(
      imageUrl: imageUrl,
      startRect: startRect,
      endRect: targetRect,
      onCompleted: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _FlyToCartImage extends StatefulWidget {
  final String? imageUrl;
  final Rect startRect;
  final Rect endRect;
  final VoidCallback onCompleted;

  const _FlyToCartImage({
    required this.imageUrl,
    required this.startRect,
    required this.endRect,
    required this.onCompleted,
  });

  @override
  State<_FlyToCartImage> createState() => _FlyToCartImageState();
}

class _FlyToCartImageState extends State<_FlyToCartImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Rect?> _rect;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Slower than the original 550ms - a quick flight read as a stutter
      // rather than a deliberate motion.
      duration: const Duration(milliseconds: 900),
    );
    // Eased in and out (gentle start, gentle finish) instead of rushing at
    // the end - smoother to the eye than the old easeInCubic, which felt
    // like it was speeding up and snapping into place.
    _rect = RectTween(begin: widget.startRect, end: widget.endRect).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    // Stays fully visible for most of the flight, then fades out right at
    // the end as it reaches (and visually merges into) the cart icon.
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);
    _controller.forward().whenComplete(widget.onCompleted);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // Built once and reused every tick, instead of being recreated inside
      // the builder below - rebuilding a network Image's whole widget tree
      // ~60 times a second was the main source of the dropped-frame
      // "laggy" feel, since only the position/opacity actually change frame
      // to frame.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ProductImage(imageUrl: widget.imageUrl, iconSize: 16),
      ),
      builder: (context, child) {
        final Rect rect = _rect.value ?? widget.endRect;
        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: Opacity(opacity: _opacity.value, child: child),
          ),
        );
      },
    );
  }
}
