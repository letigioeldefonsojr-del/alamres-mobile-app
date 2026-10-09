import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../core/constants.dart';
import '../../core/delivery_helpers.dart';
import '../../core/product_helpers.dart';
import '../../widgets/order_item_card.dart';

class CartOrderConfirmationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  // Only set when these items came straight from the live cart - those
  // documents get deleted once the order is placed. Left null (e.g. when
  // reordering from a past order) so nothing in the cart is touched.
  final List<DocumentReference<Map<String, dynamic>>>? cartRefs;
  final String initialAddress;

  const CartOrderConfirmationScreen({
    super.key,
    required this.items,
    this.cartRefs,
    required this.initialAddress,
  });

  @override
  State<CartOrderConfirmationScreen> createState() =>
      _CartOrderConfirmationScreenState();
}

class _CartOrderConfirmationScreenState
    extends State<CartOrderConfirmationScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isConfirming = false;
  String _customerName = '';
  late String _customerAddress;
  late final DateTime _estimatedDelivery;

  // Local, editable copies so the quantity steppers can adjust amounts (or
  // drop an item entirely) before the order is actually placed.
  late List<Map<String, dynamic>> _items;
  // The regular/discounted unit price each item actually had the last time
  // it was checked - used as the baseline _updateAmount below falls back to
  // when the stepper drops back under the wholesale threshold, instead of
  // being stuck on whatever price was last computed. No longer "untouched
  // once set": _productSubs below keeps this current, so a discount
  // starting or ending while this screen is open updates it live rather
  // than only at the moment "Confirm Order" is tapped.
  late List<double> _originalUnitPrices;
  List<DocumentReference<Map<String, dynamic>>>? _cartRefs;

  // One live listener per item with a real product behind it (mirrors the
  // Cart screen's own live-price listener) - purely a display nicety, since
  // _confirmOrder's transaction always re-checks the real price regardless.
  final List<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _productSubs = [];

  // Distance-based delivery fee - recalculated whenever the delivery
  // address changes. The app only stores addresses as text, so this
  // re-geocodes the current address and measures it against the nearest
  // branch each time (see delivery_helpers.dart).
  DeliveryFeeResult? _deliveryFeeResult;
  bool _isCalculatingFee = true;

  @override
  void initState() {
    super.initState();
    _customerAddress = widget.initialAddress;
    _estimatedDelivery = DateTime.now().add(const Duration(days: 3));
    final user = FirebaseAuth.instance.currentUser;
    _customerName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Guest');
    _items = widget.items.map((e) => Map<String, dynamic>.from(e)).toList();
    _originalUnitPrices = _items
        .map((item) => (item['unitPrice'] as num?)?.toDouble() ?? 0)
        .toList();
    _cartRefs = widget.cartRefs == null ? null : List.of(widget.cartRefs!);
    _recalculateDeliveryFee();

    for (int i = 0; i < _items.length; i++) {
      final String? productId = _items[i]['productId'] as String?;
      if (productId == null || productId.isEmpty) continue;
      _productSubs.add(
        FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .snapshots()
            .listen((snapshot) => _onLiveProductUpdate(i, snapshot)),
      );
    }
  }

  @override
  void dispose() {
    for (final sub in _productSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  // Re-derives item [index]'s regular/discounted unit price from the
  // product doc's current data and, if it actually changed, refreshes that
  // item on screen through the same path a manual quantity edit takes -
  // so wholesale-vs-retail selection and the subtotal/total stay correct
  // no matter whether the price moved because of a quantity change or a
  // live discount change.
  void _onLiveProductUpdate(
    int index,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!mounted) return;
    final data = snapshot.data();
    // Product deleted/unpublished mid-view - keep the last known price
    // rather than blanking it; _confirmOrder's transaction is the real
    // source of truth at checkout time regardless.
    if (data == null) return;

    final String? flavorName = _items[index]['flavor'] as String?;
    Map<String, dynamic>? variant;
    String? regularPriceRaw;
    if (flavorName != null) {
      final flavors =
          (data['flavors'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      for (final f in flavors) {
        if (f['name'] == flavorName) {
          variant = f;
          break;
        }
      }
      regularPriceRaw = variant?['price'] as String?;
    }
    regularPriceRaw ??= data['price'] as String?;
    if (regularPriceRaw == null || regularPriceRaw.trim().isEmpty) return;

    final double? liveRegularPrice = parsePesoAmount(
      effectivePrice(data, regularPriceRaw, variant: variant),
    );
    if (liveRegularPrice == null) return;

    _originalUnitPrices[index] = liveRegularPrice;
    // Also pick up a live wholesalePrice change so _updateAmount's own
    // wholesale lookup (which reads this item field) stays current too.
    final String? liveWholesale =
        (variant?['wholesalePrice'] as String?) ??
        (data['wholesalePrice'] as String?);
    if (liveWholesale != null) {
      _items[index] = {..._items[index], 'wholesalePrice': liveWholesale};
    }
    _updateAmount(index, (_items[index]['amount'] as num?)?.toInt() ?? 1);
  }

  Future<void> _recalculateDeliveryFee() async {
    if (_customerAddress.trim().isEmpty) {
      setState(() {
        _deliveryFeeResult = null;
        _isCalculatingFee = false;
      });
      return;
    }
    setState(() => _isCalculatingFee = true);
    final result = await computeDeliveryFee(_customerAddress);
    if (!mounted) return;
    setState(() {
      _deliveryFeeResult = result;
      _isCalculatingFee = false;
    });
  }

  // Switches an item's unit price to its cached wholesale price the
  // instant the stepper reaches kWholesaleMinimumQuantity, purely locally
  // (no network round-trip) - and back to the original retail/discounted
  // price if it's stepped back down below that. This mirrors the options
  // sheet's live behavior, so the price shown while adjusting quantity
  // here never lags behind what Confirm will actually charge. A live
  // discount change is still only caught at the moment of Confirm itself,
  // same as before this - that's a much rarer case and not what this is
  // fixing.
  void _updateAmount(int index, int newAmount) {
    if (newAmount < 1) return;
    setState(() {
      final data = _items[index];
      final double originalUnitPrice = _originalUnitPrices[index];
      double unitPrice = originalUnitPrice;

      if (newAmount >= kWholesaleMinimumQuantity) {
        final String? wholesaleRaw = data['wholesalePrice'] as String?;
        final double? wholesaleParsed =
            (wholesaleRaw != null && wholesaleRaw.trim().isNotEmpty)
            ? parsePesoAmount(wholesaleRaw)
            : null;
        if (wholesaleParsed != null && wholesaleParsed > 0) {
          unitPrice = wholesaleParsed;
        }
      }

      _items[index] = {
        ...data,
        'amount': newAmount,
        'unitPrice': unitPrice,
        'subtotal': unitPrice * newAmount,
      };
    });
  }

  double get _total {
    double total = 0;
    for (final data in _items) {
      final double unitPrice = (data['unitPrice'] as num?)?.toDouble() ?? 0;
      final int amount = (data['amount'] as num?)?.toInt() ?? 0;
      total += unitPrice * amount;
    }
    return total;
  }

  // Falls back to 0 while the fee hasn't resolved yet (still calculating,
  // or the address couldn't be geocoded) - the order can still be placed;
  // it's just flagged (see _confirmOrder) for the branch to confirm the
  // fee manually in that case.
  double get _deliveryFee => _deliveryFeeResult?.fee ?? 0;

  double get _grandTotal => _total + _deliveryFee;

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$minute $period';
  }

  Future<void> _changeAddress() async {
    final picked = await pickDeliveryAddress(context, _customerAddress);
    if (picked != null) {
      setState(() => _customerAddress = picked);
      _recalculateDeliveryFee();
    }
  }

  Future<void> _confirmOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _items.isEmpty) return;

    if (_customerAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please choose a delivery address before confirming.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isConfirming = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final ordersCollection = FirebaseFirestore.instance.collection('orders');
      final productsCollection = FirebaseFirestore.instance.collection(
        'products',
      );
      final orderRef = ordersCollection.doc();

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final Map<String, Map<String, dynamic>> stockUpdates = {};
        // Starts from each item's cart-snapshot unitPrice, then gets
        // overwritten below with a live re-check against the product doc -
        // so if a scheduled discount started or ended while this sat in
        // the cart, the order is billed today's price.
        final List<double> liveUnitPrices = List<double>.generate(
          _items.length,
          (i) => (_items[i]['unitPrice'] as num?)?.toDouble() ?? 0,
        );

        for (int i = 0; i < _items.length; i++) {
          final data = _items[i];
          final String? productId = data['productId'] as String?;
          if (productId == null) continue;

          final String? flavorName = data['flavor'] as String?;
          final int amount = (data['amount'] as num?)?.toInt() ?? 0;
          final productRef = productsCollection.doc(productId);

          stockUpdates[productId] = await readStockDeduction(
            txn,
            productRef,
            flavorName,
            amount,
          );
          liveUnitPrices[i] = await resolveLiveUnitPrice(
            txn,
            productRef,
            flavorName,
            amount,
            liveUnitPrices[i],
          );
        }

        stockUpdates.forEach((productId, update) {
          txn.update(productsCollection.doc(productId), update);
        });

        final List<Map<String, dynamic>> orderItems = [];
        double orderTotal = 0;

        for (int i = 0; i < _items.length; i++) {
          final data = _items[i];
          final double unitPrice = liveUnitPrices[i];
          final int amount = (data['amount'] as num?)?.toInt() ?? 0;
          final double subtotal = unitPrice * amount;
          orderTotal += subtotal;

          orderItems.add({
            'productId': data['productId'],
            'productName': data['productName'],
            'imageUrl': data['imageUrl'],
            'flavor': data['flavor'],
            'amount': amount,
            'unitPrice': unitPrice,
            'subtotal': subtotal,
          });
        }

        if (_cartRefs != null) {
          for (final ref in _cartRefs!) {
            txn.delete(ref);
          }
        }

        txn.set(orderRef, {
          'userId': user.uid,
          'customerName': _customerName,
          'customerAddress': _customerAddress,
          'items': orderItems,
          'itemCount': orderItems.length,
          'itemsSubtotal': orderTotal,
          'deliveryFee': _deliveryFee,
          ...(_deliveryFeeResult != null
              ? {
                  'deliveryDistanceKm': _deliveryFeeResult!.distanceKm,
                  'deliveryBranch': _deliveryFeeResult!.branchName,
                }
              // Address couldn't be geocoded (too vague, a typo, or
              // Nominatim briefly unreachable) - the order still goes
              // through rather than blocking the customer, just flagged
              // so the branch knows to confirm the real fee by hand.
              : {'deliveryFeeUnresolved': true}),
          'total': orderTotal + _deliveryFee,
          'status': 'pending',
          'estimatedDelivery': Timestamp.fromDate(_estimatedDelivery),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Order placed successfully!'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConfirming = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Confirm Order'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ITEMS (${_items.length})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No items left to order.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ...List.generate(_items.length, (index) {
                final data = _items[index];
                final int amount = (data['amount'] as num?)?.toInt() ?? 0;
                return OrderItemCard(
                  item: data,
                  onIncrement: () => _updateAmount(index, amount + 1),
                  onDecrement: amount > 1
                      ? () => _updateAmount(index, amount - 1)
                      : null,
                );
              }),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ITEMS SUBTOTAL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Text(
                          '₱${_total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'DELIVERY FEE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (_isCalculatingFee)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Calculating...',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          )
                        else if (_deliveryFeeResult != null)
                          Text(
                            '₱${_deliveryFeeResult!.fee.toStringAsFixed(2)} '
                            '(${_deliveryFeeResult!.distanceKm.toStringAsFixed(1)}km from '
                            '${_deliveryFeeResult!.branchName})',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          )
                        else
                          Text(
                            'To be confirmed',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.shade300, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '₱${_grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'CUSTOMER NAME',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _customerName,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: _changeAddress,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DELIVERY ADDRESS',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _customerAddress.trim().isEmpty
                                ? 'Tap to add an address'
                                : _customerAddress,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: _customerAddress.trim().isEmpty
                                  ? Colors.redAccent
                                  : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: primaryGreen,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'ESTIMATED DELIVERY',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(_estimatedDelivery),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      (_isConfirming || _items.isEmpty || _isCalculatingFee)
                      ? null
                      : _confirmOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _isConfirming
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Confirm Order',
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
    );
  }
}
