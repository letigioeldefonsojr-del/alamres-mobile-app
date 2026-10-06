import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../core/product_helpers.dart';
import '../../widgets/fly_to_cart_overlay.dart';
import '../../widgets/product_image.dart';
import 'order_confirmation_screen.dart';

class ProductOptionsSheet extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductOptionsSheet({super.key, required this.product});

  @override
  State<ProductOptionsSheet> createState() => _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends State<ProductOptionsSheet> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  int _selectedFlavorIndex = 0;
  int _amount = 1;
  bool _isProcessing = false;

  // Lets _handleAddToCart look up the product image's current on-screen
  // position for the "fly to cart" animation, right before this sheet closes.
  final GlobalKey _imageKey = GlobalKey();

  List<Map<String, dynamic>> get _flavors =>
      (widget.product['flavors'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];

  Map<String, dynamic>? get _selectedFlavor =>
      _flavors.isNotEmpty ? _flavors[_selectedFlavorIndex] : null;

  bool get _isAvailable {
    if (_flavors.isNotEmpty) {
      return (_selectedFlavor?['available'] as bool?) ?? false;
    }
    return (widget.product['available'] as bool?) ?? true;
  }

  // Stock for whichever flavor is currently selected (or the product's own
  // stockCount when it has no flavors) - shown to the customer next to the
  // amount stepper, and also what caps how high that stepper can go, so
  // there's no way to order more than what's actually in stock.
  int get _currentStock {
    if (_flavors.isNotEmpty) {
      return (_selectedFlavor?['stock'] as num?)?.toInt() ?? 0;
    }
    return (widget.product['stockCount'] as num?)?.toInt() ?? 0;
  }

  String get _regularPriceString {
    final flavorPrice = _selectedFlavor?['price'] as String?;
    return (flavorPrice != null && flavorPrice.isNotEmpty)
        ? flavorPrice
        : (widget.product['price'] as String? ?? '₱0');
  }

  // Discount-aware - this is what checkout actually charges, so it must
  // always go through effectivePrice() rather than reading price/flavor
  // price fields directly.
  double get _unitPrice {
    final String effective = effectivePrice(
      widget.product,
      _regularPriceString,
      variant: _selectedFlavor,
    );
    return parsePesoAmount(effective) ?? 0;
  }

  String get _priceLabel =>
      effectivePrice(widget.product, _regularPriceString, variant: _selectedFlavor);

  bool get _isOnSale =>
      isDiscountVisible(widget.product, variant: _selectedFlavor);

  String? get _regularPriceLabel {
    if (!_isOnSale) return null;
    return discountRegularPriceLabel(
      widget.product,
      _regularPriceString,
      variant: _selectedFlavor,
    );
  }

  String? get _discountEndLabel {
    if (!_isOnSale) return null;
    final end = widget.product['discountEnd'];
    if (end is! Timestamp) return null;
    return 'Ends ${formatDiscountDate(end.toDate())}';
  }

  // Wholesale is purely informational here (and on the product card) -
  // checkout always charges the retail _unitPrice above. Mirrors
  // _unitPrice's own fallback: the selected flavor's own wholesalePrice if
  // it has one, otherwise the product's. Null (not "₱0.00") when neither
  // is set, so the UI can just skip showing a wholesale line.
  String? get _unitWholesaleLabel {
    final flavorWholesale = _selectedFlavor?['wholesalePrice'] as String?;
    final String? raw = (flavorWholesale != null && flavorWholesale.isNotEmpty)
        ? flavorWholesale
        : (widget.product['wholesalePrice'] as String?);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  void _incrementAmount() {
    if (_amount >= _currentStock) return;
    setState(() => _amount++);
  }

  void _decrementAmount() {
    if (_amount > 1) setState(() => _amount--);
  }

  bool _checkAvailable() {
    if (_isAvailable) return true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Out of Stock'),
        content: const Text('This item is currently out of stock.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    return false;
  }

  void _handleOrderNow() {
    if (_isProcessing) return;
    if (!_checkAvailable()) return;

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderConfirmationScreen(
          product: widget.product,
          flavor: _selectedFlavor,
          amount: _amount,
          unitPrice: _unitPrice,
        ),
      ),
    );
  }

  Future<void> _handleAddToCart() async {
    if (_isProcessing) return;
    if (!_checkAvailable()) return;

    setState(() => _isProcessing = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Everything the fly-to-cart animation needs has to be captured *before*
    // this sheet closes (and before the `await` below, since the sheet's
    // own context stops being valid once it's popped) - the root overlay so
    // the flight survives the sheet's closing transition, the image's
    // current on-screen rect, and the screen metrics for the no-cart-icon
    // fallback target.
    final overlay = Overlay.of(context, rootOverlay: true);
    final Size screenSize = MediaQuery.of(context).size;
    final double topPadding = MediaQuery.of(context).padding.top;
    final renderObject = _imageKey.currentContext?.findRenderObject();
    Rect? imageRect;
    if (renderObject is RenderBox && renderObject.attached) {
      final Offset topLeft = renderObject.localToGlobal(Offset.zero);
      imageRect = topLeft & renderObject.size;
    }
    final String? imageUrl =
        (_selectedFlavor?['imageUrl'] as String?) ??
        widget.product['imageUrl'] as String?;

    try {
      await addProductToCart(
        product: widget.product,
        flavor: _selectedFlavor,
        amount: _amount,
        unitPrice: _unitPrice,
      );
      navigator.pop();
      // Stay on the current screen instead of navigating to the cart - the
      // animation plus a snackbar is confirmation enough, and the cart
      // badge's own count updates on its own once the write above lands.
      if (imageRect != null) {
        flyToCart(
          overlay,
          imageUrl: imageUrl,
          startRect: imageRect,
          screenSize: screenSize,
          topPadding: topPadding,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Added to cart'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.product['name'] as String? ?? '';
    final String price = _priceLabel;
    final String? regularPriceLabel = _regularPriceLabel;
    final String? discountBadge = _isOnSale
        ? discountPercentLabel(widget.product)
        : null;
    final String? discountEndLabel = _discountEndLabel;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                Stack(
                  key: _imageKey,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ProductImage(
                        imageUrl:
                            (_selectedFlavor?['imageUrl'] as String?) ??
                            widget.product['imageUrl'] as String?,
                        iconSize: 36,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    // Same amber accent treatment as the product card's
                    // badge, on the image rather than inline with the
                    // price - so it never collides with the discount
                    // banner shown next to the price below.
                    if (isBestSeller(widget.product))
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                color: Colors.white,
                                size: 11,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Best Seller',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (regularPriceLabel != null)
                          Text(
                            regularPriceLabel,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              price,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: regularPriceLabel != null
                                    ? Colors.redAccent
                                    : primaryGreen,
                              ),
                            ),
                            if (discountBadge != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Discounted -$discountBadge%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (discountEndLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              discountEndLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        // Informational only - checkout still charges
                        // retail (price above).
                        if (_unitWholesaleLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Wholesale: $_unitWholesaleLabel',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (_isAvailable ? primaryGreen : Colors.redAccent)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isAvailable ? 'Available' : 'Out of Stock',
                        style: TextStyle(
                          color: _isAvailable ? primaryGreen : Colors.redAccent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                if (_flavors.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'FLAVOR',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: List.generate(_flavors.length, (index) {
                      final flavor = _flavors[index];
                      final bool selected = index == _selectedFlavorIndex;
                      final bool available =
                          (flavor['available'] as bool?) ?? false;
                      final String flavorRegularRaw =
                          flavor['price'] as String? ?? '';
                      final bool flavorOnSale =
                          available &&
                          isDiscountVisible(widget.product, variant: flavor);
                      final String flavorPriceLabel = flavorRegularRaw.isEmpty
                          ? ''
                          : effectivePrice(
                              widget.product,
                              flavorRegularRaw,
                              variant: flavor,
                            );
                      final String? flavorRegularLabel = flavorOnSale
                          ? discountRegularPriceLabel(
                              widget.product,
                              flavorRegularRaw,
                              variant: flavor,
                            )
                          : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: selected
                              ? primaryGreen.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: available
                                ? () => setState(() {
                                    _selectedFlavorIndex = index;
                                    // The amount picked for the previous
                                    // flavor might not fit this one's
                                    // stock - bring it down to whatever
                                    // this flavor actually has.
                                    final int newStock =
                                        (flavor['stock'] as num?)?.toInt() ??
                                        0;
                                    if (newStock <= 0) {
                                      _amount = 1;
                                    } else if (_amount > newStock) {
                                      _amount = newStock;
                                    }
                                  })
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? primaryGreen
                                      : const Color(0xFFF0F0F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: available
                                        ? primaryGreen
                                        : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 8),
                                  if ((flavor['imageUrl'] as String?)
                                          ?.isNotEmpty ??
                                      false) ...[
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: ProductImage(
                                        imageUrl: flavor['imageUrl'] as String?,
                                        iconSize: 12,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      flavor['name'] as String? ?? '',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: available
                                            ? Colors.black87
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (flavorRegularLabel != null)
                                        Text(
                                          flavorRegularLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                      Text(
                                        available
                                            ? '$flavorPriceLabel '
                                                  '• ${flavor['stock']} pcs'
                                            : 'Out of stock',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: flavorOnSale
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: !available
                                              ? Colors.redAccent
                                              : flavorOnSale
                                              ? Colors.redAccent
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                      if (available &&
                                          ((flavor['wholesalePrice']
                                                      as String?)
                                                  ?.trim()
                                                  .isNotEmpty ??
                                              false))
                                        Text(
                                          'Wholesale: ${flavor['wholesalePrice']}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],

                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'AMOUNT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    // Visible right where the customer is picking how many
                    // to order, not just buried on the product listing -
                    // and it's the stock for whichever flavor is currently
                    // selected, not just the product's total.
                    Text(
                      _currentStock > 0
                          ? '$_currentStock pcs available'
                          : 'Out of stock',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _currentStock > 0
                            ? Colors.grey.shade600
                            : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _AmountButton(
                      icon: Icons.remove,
                      onTap: _amount > 1 ? _decrementAmount : null,
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_amount',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    _AmountButton(
                      icon: Icons.add,
                      onTap: _amount < _currentStock ? _incrementAmount : null,
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isAvailable && !_isProcessing)
                        ? _handleOrderNow
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Proceed to Order',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: (_isAvailable && !_isProcessing)
                        ? _handleAddToCart
                        : null,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryGreen, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: primaryGreen,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(
                            Icons.shopping_cart_outlined,
                            color: primaryGreen,
                            size: 18,
                          ),
                    label: const Text(
                      'Add to Cart',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: primaryGreen,
                      ),
                    ),
                  ),
                ),
                _buildRelatedProducts(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedProducts() {
    final String? category = widget.product['category'] as String?;
    if (category == null || category.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('products')
          .where('category', isEqualTo: category)
          .limit(12)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final String? currentId = widget.product['id'] as String?;
        final String currentName = widget.product['name'] as String? ?? '';

        final related = snapshot.data!.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .where(
              (p) => currentId != null
                  ? p['id'] != currentId
                  : (p['name'] as String? ?? '') != currentName,
            )
            .take(6)
            .toList();

        if (related.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 22),
            const Text(
              'YOU MAY ALSO LIKE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 134,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = related[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      showProductOptions(context, product: item);
                    },
                    child: Container(
                      width: 104,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFF0F0F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(11),
                            ),
                            child: SizedBox(
                              height: 72,
                              width: double.infinity,
                              child: ProductImage(
                                imageUrl: item['imageUrl'] as String?,
                                iconSize: 22,
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  effectivePriceLabel(item),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AmountButton extends StatelessWidget {
  final IconData icon;
  // Null (rather than a callback that does nothing) so the button can
  // actually render as visibly disabled - used when decrementing would
  // go below 1, or incrementing would go past the available stock.
  final VoidCallback? onTap;

  const _AmountButton({required this.icon, required this.onTap});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Material(
      color: enabled
          ? primaryGreen.withValues(alpha: 0.08)
          : Colors.grey.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: enabled ? primaryGreen : Colors.grey.shade400,
            size: 20,
          ),
        ),
      ),
    );
  }
}
