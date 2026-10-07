import 'dart:math';
import 'package:flutter/material.dart';

// Curated gradient pairs used as a placeholder background whenever a
// product has no image attached, instead of a flat grey box. Picked to
// stay fairly muted/pastel so the centered icon on top still reads clearly.
const List<List<Color>> _placeholderGradients = [
  [Color(0xFFFFC371), Color(0xFFFF5F6D)],
  [Color(0xFF43C6AC), Color(0xFF191654)],
  [Color(0xFF4568DC), Color(0xFFB06AB3)],
  [Color(0xFFF7971E), Color(0xFFFFD200)],
  [Color(0xFF56AB2F), Color(0xFFA8E063)],
  [Color(0xFF2E6B3E), Color(0xFF90C590)],
  [Color(0xFFEE9CA7), Color(0xFFFFDDE1)],
  [Color(0xFF6A85B6), Color(0xFFBAC8E0)],
];

// Public so other spots with their own "no image" placeholder - e.g. the
// Home tab's store banner - can reuse the same curated palette and picking
// logic instead of rendering a flat color.
List<Color> placeholderGradientFor(String? seedText) {
  final String text = (seedText == null || seedText.trim().isEmpty)
      ? 'almares-328'
      : seedText.trim().toLowerCase();
  final int index = text.hashCode.abs() % _placeholderGradients.length;
  return _placeholderGradients[index];
}

// A fresh random pick from the same palette, rather than a seeded one - for
// the one spot (the Home tab's store banner) where staying consistent
// between rebuilds doesn't matter as much as not always landing on the
// same gradient every time a banner is saved.
final Random _placeholderRandom = Random();

List<Color> randomPlaceholderGradient() {
  return _placeholderGradients[_placeholderRandom.nextInt(
    _placeholderGradients.length,
  )];
}

class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double iconSize;
  final BorderRadius borderRadius;
  // Used to deterministically pick a placeholder gradient color when there's
  // no image - e.g. the product name, so the same product always gets the
  // same color instead of a random one on every rebuild. Optional: callers
  // that don't have an obvious seed (a generic banner, the fly-to-cart
  // overlay) can simply omit it and get a default gradient.
  final String? seedText;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.iconSize = 32,
    this.borderRadius = BorderRadius.zero,
    this.seedText,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      final List<Color> gradient = placeholderGradientFor(seedText);
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: borderRadius,
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: Colors.white.withValues(alpha: 0.85),
            size: iconSize,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: const Color(0xFFF4F4F4),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F4),
            borderRadius: borderRadius,
          ),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.grey,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
