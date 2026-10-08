import 'package:flutter/material.dart';
import 'cart_badge.dart';
import '../screens/customer/cart_screen.dart';

/// A small reusable "go to cart" button with a live item-count badge - used
/// on every main browsing screen (Categories tab, product listings) so the
/// cart is always one tap away, the same way Home's own header cart icon
/// works.
///
/// Deliberately NOT wired to cart_fly_anchor.dart's `cartIconKey` - that key
/// is reserved specifically for Home's icon as the "fly to cart" add-to-cart
/// animation's primary landing target. Screens using this widget instead
/// just fall back to that animation's generic top-right landing spot, which
/// is fine since this button's only job is reliable navigation to the cart,
/// not being an animation target.
class CartIconButton extends StatelessWidget {
  // White for use on the app's green AppBars/headers, primaryGreen for use
  // on a white background (e.g. the Categories tab's own header).
  final Color color;
  // The badge's thin outline - should match whatever background the badge
  // is sitting on top of, same reasoning as the ring around Home's badge.
  final Color badgeBorderColor;

  const CartIconButton({
    super.key,
    this.color = Colors.white,
    this.badgeBorderColor = const Color(0xFF2E6B3E),
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Cart',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CartScreen()),
        );
      },
      icon: SizedBox(
        width: 26,
        height: 26,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(Icons.shopping_cart_outlined, color: color, size: 22),
            ),
            Positioned(
              top: -4,
              right: -6,
              child: CartBadge(borderColor: badgeBorderColor),
            ),
          ],
        ),
      ),
    );
  }
}
