import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../core/order_helpers.dart';
import '../../services/supabase_products.dart';
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

class _OrderDetailsScreenState extends State<OrderDetailsScreen>
    with WidgetsBindingObserver {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isCancelling = false;
  final bool _showAllItems = false;
  // Delivery is confirmed by the admin side marking the order "Delivered" -
  // there's no separate customer confirmation step. This just makes sure
  // the rating prompt (see _buildBody) only auto-opens once per time this
  // screen is on screen, rather than re-popping on every refetch while the
  // order stays delivered-and-unrated.
  bool _hasPromptedRatingThisSession = false;

  // Was a live `.snapshots()` listener on this one order document, kept
  // open for as long as this screen stayed on screen - most of that time
  // nothing about the order is actually changing. Starts from whatever
  // the orders list already had on hand (no flash of a blank screen),
  // then one real `.get()` to make sure it's current, refetched on
  // pull-to-refresh and on resuming the app. Cancelling or rating updates
  // this local copy immediately (no extra read needed to see your own
  // write) and fires [notifyOrdersChanged] so the orders list behind this
  // screen picks it up too.
  late Map<String, dynamic> _data = Map<String, dynamic>.from(widget.data);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchLatest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchLatest();
    }
  }

  Future<void> _fetchLatest() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();
      final fresh = doc.data();
      if (fresh != null && mounted) {
        setState(() => _data = fresh);
      }
    } catch (_) {
      // Keep showing whatever's already on screen - the passed-in data,
      // or the last successful fetch.
    }
  }

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
  // for now - nothing is written to the order's `rating` field unless the
  // customer taps Submit Feedback - but either way it marks the order as
  // "already prompted" (via `ratingPromptDismissed`) so the auto-popup in
  // _buildBody never comes back on its own for this order again. The
  // "Rate This Order" button stays available either way, for the customer
  // to open this same dialog manually whenever they want.
  Future<void> _showRatingDialog() async {
    int rating = 0;
    final feedbackController = TextEditingController();
    bool isSubmitting = false;

    final bool? ratingSubmitted = await showDialog<bool>(
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
                          onPressed: () =>
                              Navigator.pop(dialogContext, false),
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
                                  bool saved = false;
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
                                    saved = true;
                                  } catch (_) {
                                    // Best-effort - rating is optional, so a
                                    // failed write just gets silently dropped
                                    // rather than blocking the customer. The
                                    // dialog still closes as if dismissed
                                    // (see `ratingSubmitted` below), so the
                                    // "Rate This Order" button is still
                                    // there for a retry later.
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext, saved);
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

    if (ratingSubmitted == true) {
      if (mounted) {
        setState(() {
          _data = {
            ..._data,
            'rating': rating,
            'feedback': feedbackController.text.trim(),
          };
        });
      }
      // No live listener anymore to pick this up on its own - let the
      // orders list behind this screen know a rating just landed.
      notifyOrdersChanged();
    } else {
      // Dismissed via the X or by tapping outside the dialog, or the
      // Firestore write above failed - either way, no rating landed, but
      // the order is still "already prompted" from here on. Best-effort:
      // if this write itself fails (e.g. offline), the auto-popup may
      // show again next time, which is an acceptable fallback rather than
      // blocking anything.
      if (mounted) {
        setState(() => _data = {..._data, 'ratingPromptDismissed': true});
      }
      unawaited(
        FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .update({'ratingPromptDismissed': true})
            .catchError((_) {}),
      );
    }
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
                              // Was autofocus: true - popped the keyboard
                              // open the instant "Other" was picked, before
                              // the customer had tapped this field at all.
                              // Now it only opens once they actually tap in.
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

      // Gives back whatever this order's own app_apply_sale deducted at
      // checkout - only relevant when products actually live on Supabase
      // (see kUseSupabaseProducts); the old Firestore-only stock path is
      // untouched. restock() is best-effort and never throws (see its doc
      // comment in supabase_products.dart), so a failure here can't undo
      // the cancellation above or need its own error message - the
      // cancellation the customer asked for has already succeeded either
      // way.
      if (kUseSupabaseProducts) {
        await SupabaseProductsApi.instance.restock(ref: widget.orderId);
      }

      _data = {..._data, 'status': 'cancelled', 'cancelReason': reason};
      // No live listener anymore to pick this up on its own - let the
      // orders list behind this screen know right away.
      notifyOrdersChanged();

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
    final String? fulfillmentType = data['fulfillmentType'] as String?;
    final bool isPickup = fulfillmentType == 'pickup';
    final String? pickupBranch = data['pickupBranch'] as String?;

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
    // Once the order is actually out for delivery, the original "3 days
    // from when you ordered" estimate stops being the useful number - what
    // matters now is just whether it's coming today or tomorrow. 8 PM is
    // the cutoff: marked on_the_way before 8 PM, it's still arriving
    // today; after that, it's realistically a tomorrow delivery.
    if (status.toLowerCase() == 'on_the_way') {
      deliveryLabel = DateTime.now().hour < 20 ? 'Today' : 'Tomorrow';
    }

    final bool isRejectedOrCancelled =
        status == 'rejected' ||
        status == 'cancelled' ||
        status == 'undelivered';
    final String? deliveryIssueReason = data['deliveryIssueReason'] as String?;
    final String? cancelReason = data['cancelReason'] as String?;
    final String? rejectReason = data['rejectReason'] as String?;
    // Pickup orders follow their own admin-side lifecycle (ready_for_pickup
    // instead of on_the_way) - never both in the same order, so this picks
    // whichever 4-stage list actually matches how this particular order
    // will progress.
    final List<String> stageOrder = isPickup
        ? ['pending', 'approved', 'ready_for_pickup', 'delivered']
        : ['pending', 'approved', 'on_the_way', 'delivered'];
    final int currentStageIndex = stageOrder.indexOf(status);

    // Delivery is confirmed the moment the admin side marks the order
    // "Delivered" - there's no separate customer confirmation step. Instead,
    // the feedback prompt itself is what greets the customer: the first
    // time they open (or are already on) this screen for an order that's
    // delivered and not yet rated, the rating dialog pops up on its own.
    if (status.toLowerCase() == 'delivered' &&
        data['rating'] == null &&
        data['ratingPromptDismissed'] != true &&
        !_hasPromptedRatingThisSession) {
      _hasPromptedRatingThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRatingDialog();
      });
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                    label: isPickup ? 'Ready for Pickup' : 'On the Way',
                    reached: currentStageIndex >= 2,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: isPickup ? 'Picked Up' : 'Delivered',
                    reached: currentStageIndex >= 3,
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
            if ((status == 'undelivered' && deliveryIssueReason != null) ||
                (status == 'cancelled' && cancelReason != null) ||
                (status == 'rejected' &&
                    rejectReason != null &&
                    rejectReason.isNotEmpty)) ...[
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
                                : status == 'rejected'
                                ? 'Order Rejected'
                                : 'Unable to be Delivered',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            status == 'rejected'
                                ? 'Reason for rejection: $rejectReason'
                                : 'Reason: ${status == 'cancelled' ? cancelReason : deliveryIssueReason}',
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
            if (status == 'ready_for_pickup') ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: primaryGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront,
                      color: primaryGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (pickupBranch != null && pickupBranch.isNotEmpty)
                            ? 'Your order is ready! Pick it up at $pickupBranch.'
                            : 'Your order is ready! Pick it up in store.',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryGreen,
                          fontSize: 13.5,
                        ),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: primaryGreen, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      isPickup ? 'Paid and Picked Up' : 'Paid and Delivered',
                      style: const TextStyle(
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

            if (isPickup) ...[
              if (pickupBranch != null && pickupBranch.isNotEmpty) ...[
                Text(
                  'PICKUP BRANCH',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pickupBranch,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ] else if (customerAddress.isNotEmpty) ...[
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

            // No estimate shown for pickup orders - "ready for pickup" is
            // a store-driven status (admin marks it), not a predictable
            // date the way a delivery window is.
            if (!isPickup) ...[
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
            ],

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
                    orderStatusLabel(status, fulfillmentType: fulfillmentType),
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
      body: RefreshIndicator(
        color: primaryGreen,
        onRefresh: _fetchLatest,
        child: _buildBody(context, _data),
      ),
    );
  }
}
