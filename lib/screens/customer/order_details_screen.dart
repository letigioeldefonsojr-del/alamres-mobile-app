import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/order_helpers.dart';
import '../../widgets/order_item_card.dart';
import '../order_items_list_screen.dart';
import 'cart_order_confirmation_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.data,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _TrackingStep extends StatelessWidget {
  final String label;
  final bool reached;
  final bool isLast;

  const _TrackingStep({
    required this.label,
    required this.reached,
    required this.isLast,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final Color color = reached ? primaryGreen : Colors.grey.shade300;
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 3,
                  color: label == 'Pending' ? Colors.transparent : color,
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(height: 3, color: Colors.grey.shade300),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
              color: reached ? primaryGreen : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isCancelling = false;
  final bool _showAllItems = false;
  // Delivery is confirmed by the admin side marking the order "Delivered" -
  // there's no separate customer confirmation step. This just makes sure
  // the rating prompt (see _buildBody) only auto-opens once per time this
  // screen is on screen, rather than re-popping on every Firestore
  // snapshot rebuild while the order stays delivered-and-unrated.
  bool _hasPromptedRatingThisSession = false;

  // Goes straight to the order-confirmation screen with this order's items
  // pre-filled - it never touches the live cart, so tapping "Order Again"
  // more than once never stacks up quantities.
  void _retryOrder(Map<String, dynamic> data) {
    final items = getOrderItems(data);
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This order has no items to reorder.'),
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

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CartOrderConfirmationScreen(
          items: items,
          initialAddress: data['customerAddress'] as String? ?? '',
        ),
      ),
    );
  }

  // Shows a dismissible "rate your order" popup with a 5-star picker and an
  // optional feedback field. Closing via the X (or tapping outside) skips it
  // entirely - nothing is written unless the customer taps Submit Feedback.
  Future<void> _showRatingDialog() {
    int rating = 0;
    final feedbackController = TextEditingController();
    bool isSubmitting = false;

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Rate Your Order',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 8),
                      child: Text(
                        'How was your experience? This is optional.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final int starValue = index + 1;
                        return IconButton(
                          onPressed: () =>
                              setDialogState(() => rating = starValue),
                          icon: Icon(
                            starValue <= rating
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 32,
                          ),
                        );
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextField(
                        controller: feedbackController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Tell us more (optional)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (rating == 0 || isSubmitting)
                              ? null
                              : () async {
                                  setDialogState(() => isSubmitting = true);
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('orders')
                                        .doc(widget.orderId)
                                        .update({
                                          'rating': rating,
                                          'feedback': feedbackController.text
                                              .trim(),
                                          'ratedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                  } catch (_) {
                                    // Best-effort - rating is optional, so a
                                    // failed write just gets silently dropped
                                    // rather than blocking the customer.
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Submit Feedback',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static const List<String> _cancelReasons = [
    'Changed my mind',
    'Ordered by mistake',
    'Found a better price elsewhere',
    'Delivery is taking too long',
    'Item no longer needed',
    'Other (please specify)',
  ];

  Future<String?> _pickCancelReason() {
    String? selected;
    final otherController = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bool isOther = selected == _cancelReasons.last;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
                          child: Text(
                            'Why do you want to cancel your order?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ..._cancelReasons.map(
                          (reason) => RadioListTile<String>(
                            value: reason,
                            groupValue: selected,
                            activeColor: primaryGreen,
                            title: Text(
                              reason,
                              style: const TextStyle(fontSize: 14),
                            ),
                            onChanged: (value) =>
                                setSheetState(() => selected = value),
                          ),
                        ),
                        if (isOther)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: TextField(
                              controller: otherController,
                              autofocus: true,
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Please specify',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: selected == null
                                  ? null
                                  : () {
                                      final String reasonText = isOther
                                          ? otherController.text.trim()
                                          : selected!;
                                      if (reasonText.isEmpty) return;
                                      Navigator.pop(context, reasonText);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: const Text(
                                'Submit & Cancel Order',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _cancelOrder() async {
    final reason = await _pickCancelReason();
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _isCancelling = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({'status': 'cancelled', 'cancelReason': reason});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Order cancelled.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not cancel order. Please try again.'),
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

  Widget _buildBody(BuildContext context, Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toString();
    final List<Map<String, dynamic>> orderItems = getOrderItems(data);
    final double total =
        (data['total'] as num?)?.toDouble() ??
        orderItems.fold<double>(
          0,
          (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0),
        );
    final String customerName = data['customerName'] as String? ?? '';
    final String customerAddress = data['customerAddress'] as String? ?? '';

    final createdAt = data['createdAt'];
    String createdLabel = '—';
    if (createdAt is Timestamp) {
      createdLabel = _formatDate(createdAt.toDate());
    }

    final estimatedDelivery = data['estimatedDelivery'];
    String deliveryLabel = '—';
    if (estimatedDelivery is Timestamp) {
      deliveryLabel = _formatDate(estimatedDelivery.toDate());
    }

    final bool isRejectedOrCancelled =
        status == 'rejected' ||
        status == 'cancelled' ||
        status == 'undelivered';
    final String? deliveryIssueReason = data['deliveryIssueReason'] as String?;
    final String? cancelReason = data['cancelReason'] as String?;
    const stageOrder = ['pending', 'approved', 'on_the_way', 'delivered'];
    final int currentStageIndex = stageOrder.indexOf(status);

    // Delivery is confirmed the moment the admin side marks the order
    // "Delivered" - there's no separate customer confirmation step. Instead,
    // the feedback prompt itself is what greets the customer: the first
    // time they open (or are already on) this screen for an order that's
    // delivered and not yet rated, the rating dialog pops up on its own.
    if (status.toLowerCase() == 'delivered' &&
        data['rating'] == null &&
        !_hasPromptedRatingThisSession) {
      _hasPromptedRatingThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRatingDialog();
      });
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isRejectedOrCancelled) ...[
              Row(
                children: [
                  _TrackingStep(
                    label: 'Pending',
                    reached: currentStageIndex >= 0,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: 'Confirmed',
                    reached: currentStageIndex >= 1,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: 'On the Way',
                    reached: currentStageIndex >= 2,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: 'Delivered',
                    reached: currentStageIndex >= 3,
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
            if ((status == 'undelivered' && deliveryIssueReason != null) ||
                (status == 'cancelled' && cancelReason != null)) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status == 'cancelled'
                                ? 'Order Cancelled'
                                : 'Unable to be Delivered',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reason: ${status == 'cancelled' ? cancelReason : deliveryIssueReason}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.redAccent.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (status == 'delivered' && (data['isPaid'] as bool?) == true) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: primaryGreen, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Paid and Delivered',
                      style: TextStyle(
                        color: primaryGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'ORDER ID',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '#${widget.orderId.substring(0, widget.orderId.length.clamp(0, 12)).toUpperCase()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'DATE OF ORDER',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              createdLabel,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'ITEMS (${orderItems.length})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...(_showAllItems ? orderItems.take(6) : orderItems.take(3)).map(
              (item) => OrderItemCard(item: item),
            ),
            if (orderItems.length > 6)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderItemsListScreen(
                          orderId: widget.orderId,
                          items: orderItems,
                          total: total,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'View Full Order (${orderItems.length} items)',
                        style: const TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        color: primaryGreen,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ORDER TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (customerName.isNotEmpty) ...[
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
                customerName,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (customerAddress.isNotEmpty) ...[
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
                customerAddress,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],

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
              deliveryLabel,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Text(
                  'STATUS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: orderStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    orderStatusLabel(status),
                    style: TextStyle(
                      color: orderStatusColor(status),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            if (status.toLowerCase() == 'delivered') ...[
              if (data['rating'] == null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _showRatingDialog,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    icon: const Icon(
                      Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    ),
                    label: const Text(
                      'Rate This Order',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'You rated this order ${data['rating']}/5',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 3,
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            if (status.toLowerCase() == 'cancelled') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _retryOrder(data),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  icon: const Icon(Icons.replay, color: primaryGreen, size: 18),
                  label: const Text(
                    'Order Again',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primaryGreen,
                    ),
                  ),
                ),
              ),
            ],

            if (status.toLowerCase() == 'pending') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _isCancelling ? null : _cancelOrder,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _isCancelling
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.redAccent,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Cancel Order',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                ),
              ),
            ],
            SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Order Details'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? widget.data;
          return _buildBody(context, data);
        },
      ),
    );
  }
}
