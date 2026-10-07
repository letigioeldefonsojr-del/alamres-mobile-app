import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../core/product_helpers.dart';
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
  bool _addressLoaded = false;

  // Live, discount-aware unit prices keyed by cart doc id - populated as
  // each row's product stream reports its current price, so a scheduled
  // discount starting or ending while this screen is open updates the
  // cart total without the customer needing to leave and come back.
  // Starts empty; each row falls back to its own stored unitPrice until
  // its live price arrives.
  final Map<String, double> _livePrices = {};
  final Map<String, String> _livePriceKeys = {};

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
        _addressLoaded = true;
      });
    }
  }

  Future<void> _changeAddress() async {
    final picked = await pickDeliveryAddress(context, _selectedAddress);
    if (picked != null) setState(() => _selectedAddress = picked);
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
              stream: ref.orderBy('updatedAt', descending: true).snapshots(),
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
                                        flavorName: flavor,
                                        storedUnitPrice: storedUnitPrice,
                                        knownLivePrice: _livePrices[doc.id],
                                        onLivePrice: _reportLivePrice,
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
class _LiveUnitPriceText extends StatelessWidget {
  final String docId;
  final String? productId;
  final String? flavorName;
  final double storedUnitPrice;
  final double? knownLivePrice;
  final void Function(String docId, double price) onLivePrice;

  const _LiveUnitPriceText({
    required this.docId,
    required this.productId,
    required this.flavorName,
    required this.storedUnitPrice,
    required this.knownLivePrice,
    required this.onLivePrice,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final double fallback = knownLivePrice ?? storedUnitPrice;

    if (productId == null) {
      return Text(
        '₱${fallback.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: primaryGreen,
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .snapshots(),
      builder: (context, snapshot) {
        final double displayPrice = liveUnitPriceFromProductDoc(
          snapshot.data?.data(),
          flavorName,
          fallback,
        );
        if (snapshot.hasData) {
          onLivePrice(docId, displayPrice);
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
