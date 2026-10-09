import 'package:flutter/material.dart';
import '../core/product_helpers.dart';
import 'product_image.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onImageTap;
  final bool isBestSelling;

  const ProductCard({
    super.key,
    required this.product,
    required this.onImageTap,
    this.isBestSelling = false,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final String name = product['name'] as String? ?? '';
    final String stock = productStockLabel(product);
    final String? wholesaleLabel = productWholesalePriceLabel(product);
    final bool isOutOfStock = extractTotalStock(product) <= 0;
    final bool onSale = productHasVisibleDiscount(product);
    final String price = effectivePriceLabel(product);
    // The admin-curated bestSeller field takes priority over the older
    // client-computed order-count badge - only one ever shows, so the two
    // signals never visually stack on top of each other.
    final bool adminBestSeller = isBestSeller(product);
    final bool showBestSellerBadge = adminBestSeller || isBestSelling;
    final String bestSellerLabel = adminBestSeller
        ? 'Best Seller'
        : 'BEST-SELLING';
    final String? regularPrice = onSale
        ? discountRegularPriceRangeLabel(product)
        : null;
    final String? discountPercent = onSale ? discountPercentLabel(product) : null;

    return Opacity(
      opacity: isOutOfStock ? 0.5 : 1.0,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isOutOfStock ? null : onImageTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF0F0F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColorFiltered(
                        colorFilter: isOutOfStock
                            ? const ColorFilter.matrix([
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ])
                            : const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.multiply,
                              ),
                        child: ProductImage(
                          imageUrl: product['imageUrl'] as String?,
                          seedText: name,
                          iconSize: 32,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                      ),
                      // Stacked vertically in one corner, rather than
                      // split across opposite corners - on a narrow card
                      // (e.g. the 150px-wide home carousels), "Best
                      // Seller" plus "Discounted -X%" are together wider
                      // than the card itself, so two independently
                      // positioned corner badges can visually collide.
                      // Stacking removes any horizontal competition.
                      if ((showBestSellerBadge || onSale) && !isOutOfStock)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showBestSellerBadge)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade700,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.local_fire_department,
                                        color: Colors.white,
                                        size: 11,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          bestSellerLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (showBestSellerBadge && onSale)
                                const SizedBox(height: 4),
                              if (onSale)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Discounted -$discountPercent%',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          extractTotalStock(product) <= 0
                              ? 'Out of Stock'
                              : stock,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: extractTotalStock(product) <= 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: extractTotalStock(product) <= 0
                                ? Colors.redAccent
                                : Colors.grey,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            (onSale && regularPrice != null)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        regularPrice,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.grey.shade500,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                      Text(
                                        price,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    price,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: primaryGreen,
                                    ),
                                  ),
                            // A preview only - the grid card has no amount
                            // picker, so this just lets a customer know
                            // wholesale pricing exists; it's actually
                            // applied automatically once they pick
                            // kWholesaleMinimumQuantity+ pcs in the
                            // options sheet.
                            if (wholesaleLabel != null)
                              Text(
                                'Wholesale: $wholesaleLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ],
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
