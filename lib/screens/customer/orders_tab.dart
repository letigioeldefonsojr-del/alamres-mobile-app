import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../core/order_helpers.dart';
import '../../widgets/product_image.dart';
import 'order_details_screen.dart';

class OrdersPlaceholderTab extends StatelessWidget {
  const OrdersPlaceholderTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const OrdersListView();
  }
}

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('My Orders'),
      ),
      body: const OrdersListView(),
    );
  }
}

class OrdersListView extends StatefulWidget {
  const OrdersListView({super.key});

  @override
  State<OrdersListView> createState() => _OrdersListViewState();
}

/// Was a single `.snapshots()` listener on every one of this customer's
/// orders ever placed, held open for as long as this tab was mounted - a
/// customer who's been ordering for a year paid to keep that entire
/// history "live" just to see today's status update. This now does two
/// one-time `.get()`s instead:
///   - "recent": the last [_recentWindow] of orders, newest first, paged
///     in batches of [_pageSize] via `startAfterDocument` behind a
///     "Load older orders" button - covered by the project's existing
///     (userId, createdAt) composite index.
///   - "active": every order in [_activeStatuses] regardless of age (a
///     pure multi-equality query, no composite index needed) - so an
///     order placed 6 weeks ago that's still `pending` never silently
///     drops out of view just because it's outside the recent window.
/// Both are merged (deduped by order id) and sorted newest-first for
/// display. Refetched on pull-to-refresh, on resuming the app, and via
/// [ordersChangedSignal] right after this same customer places, cancels,
/// or rates an order - never on a timer, and never just because some
/// other screen rebuilt.
class _OrdersListViewState extends State<OrdersListView>
    with WidgetsBindingObserver {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  static const Duration _recentWindow = Duration(days: 30);
  static const int _pageSize = 30;
  static const List<String> _activeStatuses = [
    'pending',
    'approved',
    'ready_for_pickup',
    'on_the_way',
  ];

  String? _selectedStatus;

  static const List<Map<String, String>> _statusOptions = [
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'approved', 'label': 'Approved'},
    {'value': 'ready_for_pickup', 'label': 'Ready for Pickup'},
    {'value': 'on_the_way', 'label': 'On Its Way'},
    {'value': 'delivered', 'label': 'Delivered'},
    {'value': 'cancelled', 'label': 'Cancelled'},
    {'value': 'undelivered', 'label': 'Unable to Deliver'},
  ];

  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  Object? _lastError;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _recentDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _activeDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastRecentDoc;
  bool _hasMoreRecent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
    ordersChangedSignal.addListener(_loadInitial);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ordersChangedSignal.removeListener(_loadInitial);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInitial();
    }
  }

  Color _statusColor(String status) => orderStatusColor(status);

  // --- Data -------------------------------------------------------------

  Future<void> _loadInitial() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) setState(() => _error = false);

    try {
      final Timestamp cutoff = Timestamp.fromDate(
        DateTime.now().subtract(_recentWindow),
      );
      final recentFuture = FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();
      final activeFuture = FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: _activeStatuses)
          .get();

      final results = await Future.wait([recentFuture, activeFuture]);
      final recentSnap =
          results[0] as QuerySnapshot<Map<String, dynamic>>;
      final activeSnap =
          results[1] as QuerySnapshot<Map<String, dynamic>>;

      if (!mounted) return;
      setState(() {
        _recentDocs = recentSnap.docs;
        _activeDocs = activeSnap.docs;
        _lastRecentDoc = recentSnap.docs.isNotEmpty
            ? recentSnap.docs.last
            : null;
        _hasMoreRecent = recentSnap.docs.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _lastError = e;
      });
    }
  }

  Future<void> _loadMoreRecent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _loadingMore || !_hasMoreRecent) return;
    final DocumentSnapshot<Map<String, dynamic>>? after = _lastRecentDoc;
    if (after == null) return;

    setState(() => _loadingMore = true);
    try {
      final Timestamp cutoff = Timestamp.fromDate(
        DateTime.now().subtract(_recentWindow),
      );
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(after)
          .limit(_pageSize)
          .get();

      if (!mounted) return;
      setState(() {
        _recentDocs = [..._recentDocs, ...snap.docs];
        if (snap.docs.isNotEmpty) _lastRecentDoc = snap.docs.last;
        _hasMoreRecent = snap.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // --- Merge / filter -----------------------------------------------------

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _mergedDocs {
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> byId = {};
    for (final doc in _recentDocs) {
      byId[doc.id] = doc;
    }
    // Active orders are added last so one that's also inside the recent
    // window doesn't get counted/shown twice.
    for (final doc in _activeDocs) {
      byId[doc.id] = doc;
    }
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> merged = byId
        .values
        .toList();
    merged.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      final int ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
      final int mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
      return mb.compareTo(ma);
    });
    return merged;
  }

  Future<void> _pickStatus() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Filter by Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.all_inclusive,
                      color: primaryGreen,
                    ),
                    title: const Text('All'),
                    trailing: _selectedStatus == null
                        ? const Icon(Icons.check, color: primaryGreen)
                        : null,
                    onTap: () => Navigator.pop(context, null),
                  ),
                  const Divider(height: 1),
                  ..._statusOptions.map((option) {
                    final bool isSelected = _selectedStatus == option['value'];
                    return ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: orderStatusColor(option['value']!),
                      ),
                      title: Text(option['label']!),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: primaryGreen)
                          : null,
                      onTap: () => Navigator.pop(context, option['value']),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != _selectedStatus) {
      setState(() => _selectedStatus = selected);
    }
  }

  String get _selectedStatusLabel {
    if (_selectedStatus == null) return 'All';
    return _statusOptions.firstWhere(
      (o) => o['value'] == _selectedStatus,
    )['label']!;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(child: Text('Please log in to view your orders.'));
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              const Text(
                "Couldn't load orders",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$_lastError',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadInitial,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs =
        _mergedDocs;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs =
        allDocs.where((doc) {
      final data = doc.data();
      return _selectedStatus == null ||
          (data['status'] ?? '').toString().toLowerCase() == _selectedStatus;
    }).toList();

    final double total = filteredDocs.fold<double>(0, (sum, doc) {
      final data = doc.data();
      final String docStatus = (data['status'] ?? '').toString().toLowerCase();
      if (docStatus == 'cancelled' ||
          docStatus == 'rejected' ||
          docStatus == 'undelivered') {
        return sum;
      }
      final totalField = data['total'];
      return sum + ((totalField is num) ? totalField.toDouble() : 0);
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Column(
        children: [
          SafeArea(
            top: true,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total (last 30 days + active)',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          '₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryGreen,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _pickStatus,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: primaryGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.filter_list,
                              color: primaryGreen,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _selectedStatusLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: primaryGreen,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: primaryGreen,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              color: primaryGreen,
              onRefresh: _loadInitial,
              child: filteredDocs.isEmpty
                  ? ListView(
                      // A ListView (not a Center) so pull-to-refresh still
                      // works when there's nothing to show yet.
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      children: [
                        Padding(
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
                                  Icons.receipt_long_outlined,
                                  color: primaryGreen,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                allDocs.isEmpty
                                    ? 'No orders yet'
                                    : 'No orders match this filter',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                allDocs.isEmpty
                                    ? 'Your order history will appear here.'
                                    : 'Try a different status, or load older orders below.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                              if (_hasMoreRecent) ...[
                                const SizedBox(height: 16),
                                _LoadOlderButton(
                                  loading: _loadingMore,
                                  onPressed: _loadMoreRecent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        20 +
                            kFabBottomClearance +
                            MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: filteredDocs.length + (_hasMoreRecent ? 1 : 0),
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == filteredDocs.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Center(
                              child: _LoadOlderButton(
                                loading: _loadingMore,
                                onPressed: _loadMoreRecent,
                              ),
                            ),
                          );
                        }

                        final data = filteredDocs[index].data();
                        final orderItems = getOrderItems(data);
                        final status = (data['status'] ?? 'pending').toString();
                        final total = data['total'];
                        final createdAt = data['createdAt'];
                        String dateLabel = '';
                        if (createdAt is Timestamp) {
                          final d = createdAt.toDate();
                          dateLabel = '${d.month}/${d.day}/${d.year}';
                        }
                        final orderId = filteredDocs[index].id;
                        final shortId = orderId.substring(
                          0,
                          orderId.length.clamp(0, 8),
                        );
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFF0F0F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              OrderDetailsScreen(
                                                orderId: orderId,
                                                data: data,
                                              ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: ProductImage(
                                              imageUrl: orderItems.isNotEmpty
                                                  ? orderItems
                                                            .first['imageUrl']
                                                        as String?
                                                  : null,
                                              seedText: orderItems.isNotEmpty
                                                  ? orderItems
                                                            .first['productName']
                                                        as String?
                                                  : null,
                                              iconSize: 22,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Order #$shortId',
                                                  style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  orderItems.length == 1
                                                      ? (orderItems
                                                                .first['productName']
                                                            as String? ??
                                                        '')
                                                      : '${orderItems.length} items',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        Colors.grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (dateLabel
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    dateLabel,
                                                    style: TextStyle(
                                                      color: Colors
                                                          .grey
                                                          .shade500,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (total != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                    right: 10,
                                                  ),
                                              child: Text(
                                                '₱${total.toString()}',
                                                style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                            decoration: BoxDecoration(
                                              color: _statusColor(
                                                status,
                                              ).withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              orderStatusLabel(
                                                status,
                                                fulfillmentType:
                                                    data['fulfillmentType']
                                                        as String?,
                                              ),
                                              style: TextStyle(
                                                color: _statusColor(status),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadOlderButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _LoadOlderButton({required this.loading, required this.onPressed});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: primaryGreen),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryGreen,
              ),
            )
          : const Icon(Icons.expand_more, color: primaryGreen, size: 18),
      label: Text(
        loading ? 'Loading...' : 'Load older orders',
        style: const TextStyle(color: primaryGreen, fontWeight: FontWeight.w600),
      ),
    );
  }
}
