import 'dart:async';

import 'package:flutter/material.dart';
import '../core/cart_helpers.dart';
import '../core/product_helpers.dart';
import 'product_image.dart';

/// The row-style counterpart to ProductCard, used when the customer has
/// picked "List" via ProductViewModeButton instead of a grid. Mirrors
/// ProductCard's logic (availability, pricing, quick-add) exactly - this
/// is a different layout for the same product, not a different feature.
class ProductListTile extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final bool isBestSelling;

  const ProductListTile({
    super.key,
    required this.product,
    required this.onTap,
    this.isBestSelling = false,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  State<ProductListTile> createState() => _ProductListTileState();
}

class _ProductListTileState extends State<ProductListTile> {
  // Same guard/feedback pattern as ProductCard's quick-add "+" - see that
  // widget's own comments for why.
  bool _isAdding = false;
  bool _justAdded = false;
  Timer? _justAddedTimer;

  static const Color primaryGreen = ProductListTile.primaryGreen;

  List<Map<String, dynamic>> get _flavors =>
      (widget.product['flavors'] as List?)
          ?.map((f) => Map<String, dynamic>.from(f as Map))
          .toList() ??
      const <Map<String, dynamic>>[];

  bool get _canQuickAdd => _flavors.length <= 1;

  @override
  void dispose() {
    _justAddedTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleQuickAdd() async {
    if (_isAdding) return;
    if (!_canQuickAdd) {
      widget.onTap();
      return;
    }

    final product = widget.product;
    if (isOutOfStock(product)) return;

    final Map<String, dynamic>? flavor = _flavors.isNotEmpty
        ? _flavors.first
        : null;
    final String regularPriceString =
        (flavor?['price'] as String?) ?? (product['price'] as String? ?? '₱0');
    final double unitPrice =
        parsePesoAmount(
          effectivePriceForQuantity(product, regularPriceString, 1, variant: flavor),
        ) ??
        0;
    final String? flavorWholesale = flavor?['wholesalePrice'] as String?;
    final String? wholesalePrice =
        (flavorWholesale != null && flavorWholesale.isNotEmpty)
        ? flavorWholesale
        : (product['wholesalePrice'] as String?);

    setState(() => _isAdding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await addProductToCart(
        product: product,
        flavor: flavor,
        amount: 1,
        unitPrice: unitPrice,
        wholesalePrice: wholesalePrice,
      );
      if (mounted) {
        setState(() => _justAdded = true);
        _justAddedTimer?.cancel();
        _justAddedTimer = Timer(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _justAdded = false);
        });
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Could not add to cart. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final String name = product['name'] as String? ?? '';
    final String stock = productStockLabel(product);
    final String? wholesaleLabel = productWholesalePriceLabel(product);
    final bool productOutOfStock = isOutOfStock(product);
    final bool onSale = productHasVisibleDiscount(product);
    final String price = effectivePriceLabel(product);
    final bool adminBestSeller = isBestSeller(product);
    final bool showBestSellerBadge = adminBestSeller || widget.isBestSelling;
    final String bestSellerLabel = adminBestSeller
        ? 'Best Seller'
        : 'BEST-SELLING';
    final String? regularPrice = onSale
        ? discountRegularPriceRangeLabel(product)
        : null;
    final String? discountPercent = onSale ? discountPercentLabel(product) : null;

    return Opacity(
      opacity: productOutOfStock ? 0.5 : 1.0,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: productOutOfStock ? null : widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF0F0F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ColorFiltered(
                      colorFilter: productOutOfStock
                          ? const ColorFilter.matrix([
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0, 0, 0, 1, 0,
                            ])
                          : const ColorFilter.mode(
                              Colors.transparent,
                              BlendMode.multiply,
                            ),
                      child: ProductImage(
                        imageUrl: product['imageUrl'] as String?,
                        seedText: name,
                        iconSize: 26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (showBestSellerBadge) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade700,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.local_fire_department,
                                    color: Colors.white,
                                    size: 9,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    bestSellerLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        productOutOfStock ? 'Out of Stock' : stock,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: productOutOfStock
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: productOutOfStock
                              ? Colors.redAccent
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (onSale && regularPrice != null) ...[
                            Text(
                              regularPrice,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade500,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            price,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: onSale ? Colors.redAccent : primaryGreen,
                            ),
                          ),
                          if (onSale && discountPercent != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '-$discountPercent%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (wholesaleLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Wholesale: $wholesaleLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!productOutOfStock) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: primaryGreen,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _handleQuickAdd,
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 150),
                            child: _isAdding
                                ? const SizedBox(
                                    key: ValueKey('spinner'),
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : _justAdded
                                ? const Icon(
                                    Icons.check,
                                    key: ValueKey('check'),
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : const Icon(
                                    Icons.add,
                                    key: ValueKey('add'),
                                    color: Colors.white,
                                    size: 18,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
