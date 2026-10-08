import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../core/delivery_helpers.dart';
import '../../core/product_helpers.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? flavor;
  final int amount;
  final double unitPrice;

  const OrderConfirmationScreen({
    super.key,
    required this.product,
    required this.flavor,
    required this.amount,
    required this.unitPrice,
  });

  @override
  State<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isLoading = true;
  bool _isConfirming = false;

  String _customerName = '';
  String _customerAddress = '';
  late final DateTime _orderTime;
  late final DateTime _estimatedDelivery;
  late final String _orderNumber;

  // Distance-based delivery fee - recalculated whenever the delivery
  // address changes. The app only stores addresses as text, so this
  // re-geocodes the current address and measures it against the nearest
  // branch each time (see delivery_helpers.dart).
  DeliveryFeeResult? _deliveryFeeResult;
  bool _isCalculatingFee = true;

  @override
  void initState() {
    super.initState();
    _orderTime = DateTime.now();
    _estimatedDelivery = _orderTime.add(const Duration(days: 3));
    _orderNumber = FirebaseFirestore.instance.collection('orders').doc().id;
    _loadCustomerInfo();
  }

  Future<void> _loadCustomerInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    _customerName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Guest');

    try {
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = doc.data();
        _customerAddress = combineAddressAndLandmark(
          (data?['address'] as String?) ?? '',
          data?['landmark'] as String?,
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _recalculateDeliveryFee();
    }
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

  // Falls back to 0 while the fee hasn't resolved yet (still calculating,
  // or the address couldn't be geocoded) - the order can still be placed;
  // it's just flagged (see _confirmOrder) for the branch to confirm the
  // fee manually in that case.
  double get _deliveryFee => _deliveryFeeResult?.fee ?? 0;

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

  Future<void> _confirmOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_customerAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please add a delivery address in your profile before ordering.',
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

    final String? productId = widget.product['id'] as String?;

    setState(() => _isConfirming = true);

    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(_orderNumber);
    // Written alongside the order in the same transaction/batch so the
    // admin panel's new-order notification can never be created without
    // the order itself (or vice versa).
    final notificationRef = FirebaseFirestore.instance
        .collection('employeeNotifications')
        .doc();

    try {
      if (productId != null) {
        final productRef = FirebaseFirestore.instance
            .collection('products')
            .doc(productId);

        final String? itemImage =
            (widget.flavor != null && widget.flavor!['imageUrl'] != null)
            ? widget.flavor!['imageUrl'] as String?
            : widget.product['imageUrl'] as String?;

        await FirebaseFirestore.instance.runTransaction((txn) async {
          final stockUpdate = await readStockDeduction(
            txn,
            productRef,
            widget.flavor?['name'] as String?,
            widget.amount,
          );
          // Re-checked against the live product doc so that if a
          // scheduled discount started or ended between opening this
          // screen and tapping Confirm, the customer is billed today's
          // price - not whatever was on screen a moment ago.
          final double unitPrice = await resolveLiveUnitPrice(
            txn,
            productRef,
            widget.flavor?['name'] as String?,
            widget.unitPrice,
          );
          final double total = unitPrice * widget.amount;
          txn.update(productRef, stockUpdate);
          txn.set(orderRef, {
            'userId': user.uid,
            'customerName': _customerName,
            'customerAddress': _customerAddress,
            'items': [
              {
                'productId': productId,
                'productName': widget.product['name'],
                'imageUrl': itemImage,
                'flavor': widget.flavor?['name'],
                'amount': widget.amount,
                'unitPrice': unitPrice,
                'subtotal': total,
              },
            ],
            'itemCount': 1,
            'itemsSubtotal': total,
            'deliveryFee': _deliveryFee,
            ...(_deliveryFeeResult != null
                ? {
                    'deliveryDistanceKm': _deliveryFeeResult!.distanceKm,
                    'deliveryBranch': _deliveryFeeResult!.branchName,
                  }
                : {'deliveryFeeUnresolved': true}),
            'total': total + _deliveryFee,
            'status': 'pending',
            'estimatedDelivery': Timestamp.fromDate(_estimatedDelivery),
            'createdAt': FieldValue.serverTimestamp(),
          });
          txn.set(notificationRef, {
            'message':
                'New order from $_customerName — ₱${total.toStringAsFixed(2)}',
            'orderId': orderRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
      } else {
        // No backing product doc to re-check a live price against, so
        // this one-off item is billed exactly what was shown.
        final double total = widget.unitPrice * widget.amount;
        final String? itemImage =
            (widget.flavor != null && widget.flavor!['imageUrl'] != null)
            ? widget.flavor!['imageUrl'] as String?
            : widget.product['imageUrl'] as String?;

        final batch = FirebaseFirestore.instance.batch();
        batch.set(orderRef, {
          'userId': user.uid,
          'customerName': _customerName,
          'customerAddress': _customerAddress,
          'items': [
            {
              'productId': null,
              'productName': widget.product['name'],
              'imageUrl': itemImage,
              'flavor': widget.flavor?['name'],
              'amount': widget.amount,
              'unitPrice': widget.unitPrice,
              'subtotal': total,
            },
          ],
          'itemCount': 1,
          'itemsSubtotal': total,
          'deliveryFee': _deliveryFee,
          ...(_deliveryFeeResult != null
              ? {
                  'deliveryDistanceKm': _deliveryFeeResult!.distanceKm,
                  'deliveryBranch': _deliveryFeeResult!.branchName,
                }
              : {'deliveryFeeUnresolved': true}),
          'total': total + _deliveryFee,
          'status': 'pending',
          'estimatedDelivery': Timestamp.fromDate(_estimatedDelivery),
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.set(notificationRef, {
          'message':
              'New order from $_customerName — ₱${total.toStringAsFixed(2)}',
          'orderId': orderRef.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Widget _detailRow(String label, String value, {bool noPadding = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double total = widget.unitPrice * widget.amount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Confirm Order'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.product['name'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                                if (widget.flavor != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Flavor: ${widget.flavor!['name']}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Qty: ${widget.amount}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _detailRow('Customer Name', _customerName),
                    GestureDetector(
                      onTap: () async {
                        final picked = await pickDeliveryAddress(
                          context,
                          _customerAddress,
                        );
                        if (picked != null) {
                          setState(() => _customerAddress = picked);
                          _recalculateDeliveryFee();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _detailRow(
                                'Customer Address',
                                _customerAddress,
                                noPadding: true,
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
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'DELIVERY FEE',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: Colors.black54,
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
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                '₱${(total + _deliveryFee).toStringAsFixed(2)}',
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
                    const SizedBox(height: 16),
                    _detailRow(
                      'Estimated Delivery',
                      _formatDate(_estimatedDelivery),
                    ),
                    _detailRow(
                      'Order Number',
                      '#${_orderNumber.substring(0, 8).toUpperCase()}',
                    ),
                    _detailRow('Time of Order', _formatDate(_orderTime)),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isConfirming || _isCalculatingFee)
                            ? null
                            : _confirmOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                          elevation: 3,
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
