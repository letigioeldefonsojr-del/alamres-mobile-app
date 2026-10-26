import 'package:flutter/material.dart';
import '../core/cart_helpers.dart';
import '../core/product_helpers.dart';
import 'added_to_cart_toast.dart';
import 'product_image.dart';

class ProductCard extends StatefulWidget {
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
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  // Guards against double-tapping the quick-add "+" button while the
  // Firestore write from a previous tap is still in flight.
  bool _isAdding = false;

  static const Color primaryGreen = ProductCard.primaryGreen;

  List<Map<String, dynamic>> get _flavors =>
      (widget.product['flavors'] as List?)
          ?.map((f) => Map<String, dynamic>.from(f as Map))
          .toList() ??
      const <Map<String, dynamic>>[];

  // The "+" only skips straight to the cart when there's nothing left for
  // the customer to decide - no flavors, or just the one. Anything with
  // more than one flavor still needs the options sheet so they can pick
  // which one, same as tapping the card itself.
  bool get _canQuickAdd => _flavors.length <= 1;

  Future<void> _handleQuickAdd() async {
    if (_isAdding) return;
    if (!_canQuickAdd) {
      widget.onImageTap();
      return;
    }

    final product = widget.product;
    final bool isOutOfStock = extractTotalStock(product) <= 0;
    if (isOutOfStock) return;

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
      // A top-anchored toast instead of a bottom SnackBar - see
      // added_to_cart_toast.dart for why: the bottom of these tabs is too
      // crowded (chat FAB, View Cart bar, tab bar) for a bottom-floating
      // confirmation to ever clear everything cleanly.
      if (mounted) showAddedToCartToast(context);
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
    final VoidCallback onImageTap = widget.onImageTap;
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
    final bool showBestSellerBadge = adminBestSeller || widget.isBestSelling;
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
                      // Quick-add "+" - the foodpanda-style one-tap add
                      // from the grid, without opening the full product
                      // sheet first. Bottom-right of the image so it never
                      // competes with the best-seller/discount badges
                      // stacked in the top-left corner above. Hidden
                      // entirely (rather than just disabled) once the
                      // product is out of stock, same as how the rest of
                      // the card already dims in that case.
                      if (!isOutOfStock)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Material(
                            color: primaryGreen,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _handleQuickAdd,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: Center(
                                  child: _isAdding
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                ),
                              ),
                            ),
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
