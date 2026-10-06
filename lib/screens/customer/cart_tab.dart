import 'package:flutter/material.dart';

class CartPlaceholderTab extends StatelessWidget {
  const CartPlaceholderTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SimplePlaceholderTab(
      icon: Icons.shopping_cart_outlined,
      title: 'My Cart',
      message: 'Items you add to your cart will appear here.',
    );
  }
}

class _SimplePlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SimplePlaceholderTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primaryGreen, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
