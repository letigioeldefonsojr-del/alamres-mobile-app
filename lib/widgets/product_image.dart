import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double iconSize;
  final BorderRadius borderRadius;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.iconSize = 32,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: borderRadius,
        ),
        child: Center(
          child: Icon(Icons.image_outlined, color: Colors.grey, size: iconSize),
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
