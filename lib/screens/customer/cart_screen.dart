import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../core/product_helpers.dart';
import '../../services/product_repository.dart';
import '../../widgets/product_image.dart';
import 'cart_order_confirmation_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final bool _isCheckingOut = false;
  final Set<String> _selectedIds = {};
  String _selectedAddress = '';
  // Exact pin coordinates for _selectedAddress, when known - carried
  // through to CartOrderConfirmationScreen so checkout doesn't have to
  // re-geocode the address text to show/store an accurate map pin.
  double? _selectedAddressLat;
  double? _selectedAddressLng;
  bool _addressLoaded = false;

  // Live, discount-aware unit prices keyed by cart doc id - populated as
  // each row's product stream reports its current price, so a scheduled
  // discount starting or ending while this screen is open updates the
  // cart total without the customer needing to leave and come back.
  // Starts empty; each row falls back to its own stored unitPrice until
  // its live price arrives.
  final Map<String, double> _livePrices = {};
  final Map<String, String> _livePriceKeys = {};

  // Cart docs whose matching product has been deleted from the catalog and
  // are already being auto-removed - tracked so _handleProductGone doesn't
  // fire _removeItem (and the SnackBar) more than once per doc while that
  // delete is still in flight (its own Firestore write triggers a rebuild,
  // and _LiveUnitPriceText's stream re-reports "gone" on every one of those
  // rebuilds until the cart doc is actually gone).
  final Set<String> _removingGoneIds = {};

  // Created once and reused across every rebuild - this is what was
  // causing the screen to flicker. `stream:` was previously being handed
  // a brand-new `ref.orderBy(...).snapshots()` call straight in build(),
  // so every setState() on this screen (a live price arriving, a quantity
  // change, the Select All postFrameCallback, etc.) created a genuinely
  // different Stream object. StreamBuilder treats a new stream instance
  // as a new subscription and resets to its ConnectionState.waiting
  // branch - the loading spinner - until the first snapshot arrives
  // again, which is the flicker: tapping the "+" quick-add writes to
  // Firestore, that write's own snapshot triggers a rebuild here once the
  // customer reaches the Cart screen, and each rebuild flashed the whole
  // list back to a spinner for a frame. Caching the stream means the same
  // Stream instance is passed every time, so StreamBuilder just keeps
  // delivering new data without ever dropping back to "waiting".
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cartStream;

  void _reportLivePrice(String docId, double price) {
    final String key = price.toStringAsFixed(2);
    if (_livePriceKeys[docId] == key) return;
    _livePriceKeys[docId] = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _livePrices[docId] = price);
    });
  }

  @override
  void initState() {
    super.initState();
    // A "Could not add to cart" error SnackBar (the "+" quick-add and the
    // product sheet's Add to Cart button both still use one for failures)
    // can still be showing when the customer taps straight through to this
    // screen - without this it keeps showing here too, sitting right on
    // top of the "Proceed to Checkout" button below (this screen has no
    // bottomNavigationBar for Scaffold to tuck a floating snackbar above,
    // unlike the product grids). Clearing it once this screen's first
    // frame is up stops it from following the customer here. Success
    // confirmations don't need this: the "+" button shows its own
    // checkmark inline, and the product sheet relies on its fly-to-cart
    // animation - neither one is a SnackBar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
    _cartStream = _cartRef?.orderBy('updatedAt', descending: true).snapshots();
    _loadDefaultAddress();
  }

  Future<void> _loadDefaultAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (mounted) {
      final data = doc.data();
      setState(() {
        _selectedAddress = combineAddressAndLandmark(
          (data?['address'] as String?) ?? '',
          data?['landmark'] as String?,
        );
        _selectedAddressLat = (data?['addressLat'] as num?)?.toDouble();
        _selectedAddressLng = (data?['addressLng'] as num?)?.toDouble();
        _addressLoaded = true;
      });
    }
  }

  Future<void> _changeAddress() async {
    final picked = await pickDeliveryAddress(context, _selectedAddress);
    if (picked != null) {
      setState(() {
        _selectedAddress = picked.address;
        _selectedAddressLat = picked.lat;
        _selectedAddressLng = picked.lng;
      });
    }
  }

  void _toggleSelected(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  void _selectAll(List<String> allIds) {
    setState(() {
      if (_selectedIds.length == allIds.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  CollectionReference<Map<String, dynamic>>? get _cartRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cart');
  }

  Future<void> _updateQuantity(String docId, int newAmount) async {
    if (newAmount <= 0) {
      await _cartRef?.doc(docId).delete();
      return;
    }
    await _cartRef?.doc(docId).update({'amount': newAmount});
  }

  Future<void> _removeItem(String docId) async {
    await _cartRef?.doc(docId).delete();
  }

  // Called when a cart row's live product stream reports that its product
  // doc no longer exists (deleted on the admin side) - previously the cart
  // kept showing that item indefinitely, still priced and still
  // checkout-able, since the cart doc itself is a standalone copy of the
  // product's name/price/image and nothing was watching for the source
  // product disappearing. This removes it here too, in real time, the same
  // way it already vanishes in real time from the product grids (which
  // listen to the products collection directly).
  void _handleProductGone(String docId, String productName) {
    if (_removingGoneIds.contains(docId)) return;
    _removingGoneIds.add(docId);
    _removeItem(docId);
    if (mounted) {
      setState(() => _selectedIds.remove(docId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            productName.trim().isEmpty
                ? 'An item in your cart is no longer available and was removed.'
                : '"$productName" is no longer available and was removed from your cart.',
          ),
          backgroundColor: Colors.grey.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // The actual delete always goes through here now - whether it's triggered
  // by the "Remove" link or (in the future) anything else - so there's
  // never a silent, un-confirmable way to drop an item from the cart.
  Future<void> _confirmRemoveItem(String docId, String productName) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove item?'),
        content: Text(
          productName.trim().isEmpty
              ? 'Remove this item from your cart?'
              : 'Remove "$productName" from your cart?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _removeItem(docId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _cartRef;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Cart'),
      ),
      body: ref == null
          ? const Center(child: Text('Please log in to view your cart.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _cartStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
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
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              color: primaryGreen,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Your cart is empty',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Items you add to your cart will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (_selectedIds.isEmpty && docs.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedIds.isEmpty) {
                      setState(
                        () => _selectedIds.addAll(docs.map((d) => d.id)),
                      );
                    }
                  });
                }

                final selectedDocs = docs
                    .where((d) => _selectedIds.contains(d.id))
                    .toList();

                double total = 0;
                for (final doc in selectedDocs) {
                  final data = doc.data();
                  final double storedUnitPrice =
                      (data['unitPrice'] as num?)?.toDouble() ?? 0;
                  final double unitPrice =
                      _livePrices[doc.id] ?? storedUnitPrice;
                  final int amount = (data['amount'] as num?)?.toInt() ?? 0;
                  total += unitPrice * amount;
                }

                final bool allSelected =
                    docs.isNotEmpty && _selectedIds.length == docs.length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: GestureDetector(
                        onTap: () => _selectAll(docs.map((d) => d.id).toList()),
                        child: Row(
                          children: [
                            Icon(
                              allSelected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: primaryGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              allSelected ? 'Deselect All' : 'Select All',
                              style: const TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          20 + MediaQuery.of(context).padding.bottom,
                        ),
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final String productName =
                              data['productName'] as String? ?? '';
                          final String? flavor = data['flavor'] as String?;
                          final String? productId =
                              data['productId'] as String?;
                          final double storedUnitPrice =
                              (data['unitPrice'] as num?)?.toDouble() ?? 0;
                          final int amount =
                              (data['amount'] as num?)?.toInt() ?? 0;
                          final bool isSelected = _selectedIds.contains(doc.id);

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryGreen.withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? primaryGreen
                                    : const Color(0xFFF0F0F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _toggleSelected(doc.id),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    color: primaryGreen,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: ProductImage(
                                    imageUrl: data['imageUrl'] as String?,
                                    seedText: productName,
                                    iconSize: 22,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        productName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      if (flavor != null &&
                                          flavor.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          flavor,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      _LiveUnitPriceText(
                                        docId: doc.id,
                                        productId: productId,
                                        productName: productName,
                                        flavorName: flavor,
                                        amount: amount,
                                        storedUnitPrice: storedUnitPrice,
                                        knownLivePrice: _livePrices[doc.id],
                                        onLivePrice: _reportLivePrice,
                                        onProductGone: _handleProductGone,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        _CartQtyButton(
                                          icon: Icons.remove,
                                          // Disabled at 1 instead of
                                          // decrementing to 0 - that used to
                                          // silently delete the item, making
                                          // this button double as an
                                          // unconfirmed remove. Removing is
                                          // only ever done through the
                                          // "Remove" link below now.
                                          onTap: amount > 1
                                              ? () => _updateQuantity(
                                                  doc.id,
                                                  amount - 1,
                                                )
                                              : null,
                                        ),
                                        SizedBox(
                                          width: 28,
                                          child: Text(
                                            '$amount',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        _CartQtyButton(
                                          icon: Icons.add,
                                          onTap: () => _updateQuantity(
                                            doc.id,
                                            amount + 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // A real gap (there was none before) so
                                    // a tap meant for the quantity row can't
                                    // land on "Remove" by accident.
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () => _confirmRemoveItem(
                                        doc.id,
                                        productName,
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: const Size(0, 0),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Remove',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              onTap: _addressLoaded ? _changeAddress : null,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    color: primaryGreen,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: !_addressLoaded
                                        ? Text(
                                            'Loading address...',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: Colors.grey.shade500,
                                            ),
                                          )
                                        : Text(
                                            _selectedAddress.trim().isEmpty
                                                ? 'Add a delivery address'
                                                : _selectedAddress,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color:
                                                  _selectedAddress
                                                      .trim()
                                                      .isEmpty
                                                  ? Colors.redAccent
                                                  : Colors.black87,
                                            ),
                                          ),
                                  ),
                                  if (_addressLoaded)
                                    const Text(
                                      'Change',
                                      style: TextStyle(
                                        color: primaryGreen,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total (${selectedDocs.length} item${selectedDocs.length == 1 ? '' : 's'})',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  '₱${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed:
                                    (_isCheckingOut ||
                                        selectedDocs.isEmpty ||
                                        _selectedAddress.trim().isEmpty)
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                CartOrderConfirmationScreen(
                                                  items: selectedDocs
                                                      .map((d) => d.data())
                                                      .toList(),
                                                  cartRefs: selectedDocs
                                                      .map((d) => d.reference)
                                                      .toList(),
                                                  initialAddress:
                                                      _selectedAddress,
                                                  initialLat:
                                                      _selectedAddressLat,
                                                  initialLng:
                                                      _selectedAddressLng,
                                                ),
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryGreen,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  elevation: 3,
                                ),
                                child: _isCheckingOut
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'Proceed to Checkout',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

// Shows a cart row's unit price, live - if the item is tied to a real
// product (productId != null), it listens to that product doc so a
// scheduled discount starting or ending while this screen is open updates
// the price on screen immediately, instead of only at checkout. Falls back
// to the cart item's own stored snapshot price for items with no
// productId (e.g. a one-off item), or until the live doc has loaded.
class _LiveUnitPriceText extends StatefulWidget {
  final String docId;
  final String? productId;
  final String productName;
  final String? flavorName;
  final int amount;
  final double storedUnitPrice;
  final double? knownLivePrice;
  final void Function(String docId, double price) onLivePrice;
  final void Function(String docId, String productName) onProductGone;

  const _LiveUnitPriceText({
    required this.docId,
    required this.productId,
    required this.productName,
    required this.flavorName,
    required this.amount,
    required this.storedUnitPrice,
    required this.knownLivePrice,
    required this.onLivePrice,
    required this.onProductGone,
  });

  @override
  State<_LiveUnitPriceText> createState() => _LiveUnitPriceTextState();
}

class _LiveUnitPriceTextState extends State<_LiveUnitPriceText> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final double fallback = widget.knownLivePrice ?? widget.storedUnitPrice;

    if (widget.productId == null) {
      return Text(
        '₱${fallback.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: primaryGreen,
        ),
      );
    }

    // ProductRepository is the single shared source of product data now
    // (Supabase or Firestore underneath, depending on kUseSupabaseProducts;
    // see product_repository.dart) - this replaces what used to be a
    // per-row Firestore .snapshots() listener on this product's own doc.
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: ProductRepository.instance.productsNotifier,
      builder: (context, products, _) {
        final data = ProductRepository.instance.byId(widget.productId!);

        // Only treated as "the admin deleted this product" once the
        // repository has actually confirmed at least one real load -
        // never off of an empty/not-yet-loaded list, which would
        // otherwise look identical to "not found" and wrongly clear out
        // every item in the cart on a cold start.
        if (data == null && ProductRepository.instance.hasRefreshedOnce) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onProductGone(widget.docId, widget.productName);
          });
          return Text(
            'No longer available',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          );
        }

        final double displayPrice = liveUnitPriceFromProductDoc(
          data,
          widget.flavorName,
          widget.amount,
          fallback,
        );
        if (data != null) {
          widget.onLivePrice(widget.docId, displayPrice);
        }
        return Text(
          '₱${displayPrice.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: primaryGreen,
          ),
        );
      },
    );
  }
}

class _CartQtyButton extends StatelessWidget {
  final IconData icon;
  // Null (rather than a no-op callback) so the button can render as
  // visibly disabled - used for the minus button once quantity hits 1.
  final VoidCallback? onTap;

  const _CartQtyButton({required this.icon, required this.onTap});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Material(
      color: enabled
          ? primaryGreen.withValues(alpha: 0.08)
          : Colors.grey.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            color: enabled ? primaryGreen : Colors.grey.shade400,
            size: 15,
          ),
        ),
      ),
    );
  }
}
