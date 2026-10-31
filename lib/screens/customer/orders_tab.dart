import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../core/order_helpers.dart';
import '../../core/read_counter.dart';
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

/// One order row for display, decoupled from which Firestore type it came
/// from. [_recentDocs]/[_activeDocs] used to hold `QueryDocumentSnapshot`s
/// straight from a query's `.docs`, but the 'removed' change Firestore
/// sends when an active order transitions to a terminal status hands back
/// a plain `DocumentSnapshot` instead (not a `QueryDocumentSnapshot` - it's
/// no longer part of any query result) - this wrapper lets both sit in the
/// same list without the snapshot-type mismatch.
class _OrderRow {
  final String id;
  final Map<String, dynamic> data;
  const _OrderRow(this.id, this.data);
}

/// Was a single `.snapshots()` listener on every one of this customer's
/// orders ever placed, held open for as long as this tab was mounted - a
/// customer who's been ordering for a year paid to keep that entire
/// history "live" just to see today's status update, when in practice
/// only the handful of orders still in progress ever actually change.
/// This now splits the two:
///   - "active" ([_activeStatuses], regardless of age - a pure
///     multi-equality query, no composite index needed): a real
///     `.snapshots()` listener, so an in-progress order's status keeps
///     updating on its own exactly like before - including an order
///     placed 6 weeks ago that's still `pending`. Attached while this
///     tab (or the app) is in the foreground, detached the moment it
///     isn't - see [didChangeAppLifecycleState] and [dispose].
///   - "history" (everything else - delivered/cancelled/rejected/
///     undelivered, or just older than [_recentWindow]): a one-time
///     `.get()`, paged in batches of [_pageSize] via `startAfterDocument`
///     behind a "Load older orders" button - covered by the project's
///     existing (userId, createdAt) composite index. Refetched on
///     pull-to-refresh, on resuming the app, and via [ordersChangedSignal]
///     right after this same customer places an order.
/// The moment an active order's status changes to something outside
/// [_activeStatuses] (delivered, cancelled, ...), Firestore's own
/// `DocumentChangeType.removed` event for it still carries that order's
/// final data - that's folded straight into the history list already in
/// memory instead of costing another read.
/// Both lists are merged (deduped by order id, active wins on overlap)
/// and sorted newest-first for display.
class _OrdersListViewState extends State<OrdersListView>
    with WidgetsBindingObserver {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  static const Duration _recentWindow = Duration(days: 30);
  static const int _pageSize = 30;
  // NOTE: the status list that should always stay visible regardless of
  // age named "preparing" as an example - this app's real order
  // lifecycle (order_helpers.dart) has no such status; the matching
  // in-progress one is `ready_for_pickup`, used here instead.
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

  List<_OrderRow> _recentDocs = [];
  List<_OrderRow> _activeDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastRecentDoc;
  bool _hasMoreRecent = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
    ordersChangedSignal.addListener(_refreshHistory);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ordersChangedSignal.removeListener(_refreshHistory);
    _detachActiveListener();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (state == AppLifecycleState.resumed) {
      if (uid != null) _attachActiveListenerIfNeeded(uid);
      _refreshHistory();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Keeping a `.snapshots()` listener open while the app is
      // backgrounded just burns reads for updates nobody's watching -
      // see [didChangeAppLifecycleState]'s resumed branch for where it
      // reattaches.
      //
      // Deliberately NOT keying off `inactive` here - that was the actual
      // bug behind active orders' status going stale until a manual
      // refresh. `inactive` fires for all sorts of things that aren't
      // really backgrounding (an incoming call, the notification shade, a
      // permission/share sheet, ...) and isn't reliably followed by a
      // `resumed` callback to reattach on. `paused` (and `detached`) are
      // the only states that actually mean "the app left the foreground."
      _detachActiveListener();
    }
  }

  Color _statusColor(String status) => orderStatusColor(status);

  // --- Data -------------------------------------------------------------

  /// First load (or pull-to-refresh / Retry): fetches the one-time
  /// history page and makes sure the active-orders listener is attached.
  Future<void> _loadInitial() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _fetchHistoryPage(uid);
    _attachActiveListenerIfNeeded(uid);
  }

  /// Re-fetches just the history page - used by [ordersChangedSignal]
  /// (right after this customer places an order) and on app resume. Never
  /// touches the active listener: a newly placed/cancelled/approved order
  /// is already covered live by it the moment Firestore syncs the write,
  /// so there's nothing extra to do for that here.
  Future<void> _refreshHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _fetchHistoryPage(uid);
  }

  Future<void> _fetchHistoryPage(String uid) async {
    if (mounted) setState(() => _error = false);
    try {
      final Timestamp cutoff = Timestamp.fromDate(
        DateTime.now().subtract(_recentWindow),
      );
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();
      ReadCounter.log('orders_tab:history', snap.docs.length);

      if (!mounted) return;
      setState(() {
        _recentDocs = snap.docs
            .map((d) => _OrderRow(d.id, d.data()))
            .toList();
        _lastRecentDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMoreRecent = snap.docs.length == _pageSize;
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

  /// A real `.snapshots()` listener on this customer's in-progress
  /// orders - small by nature (an active order is never one for long),
  /// so keeping it live costs little and is what makes status changes
  /// (admin approves/dispatches it, etc.) show up on their own, same as
  /// before this file started one-time-fetching everything else. A no-op
  /// if one's already attached, so calling this from both [_loadInitial]
  /// and the resumed branch of [didChangeAppLifecycleState] never opens a
  /// second listener on top of one that's already live.
  void _attachActiveListenerIfNeeded(String uid) {
    if (_activeSub != null) return;
    _activeSub = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: _activeStatuses)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            ReadCounter.log('orders_tab:active', snapshot.docs.length);
            // A doc that just stopped matching this active-status filter
            // has moved to a terminal status (delivered/cancelled/...) -
            // Firestore's 'removed' change still hands over that doc's
            // final data (as a plain DocumentSnapshot, not a
            // QueryDocumentSnapshot - it's no longer part of any query
            // result), so it's folded straight into the history list
            // already in memory rather than triggering another read.
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.removed) {
                final Map<String, dynamic>? movedData = change.doc.data();
                if (movedData != null) {
                  final String movedId = change.doc.id;
                  _recentDocs = [
                    ..._recentDocs.where((r) => r.id != movedId),
                    _OrderRow(movedId, movedData),
                  ];
                }
              }
            }
            setState(() {
              _activeDocs = snapshot.docs
                  .map((d) => _OrderRow(d.id, d.data()))
                  .toList();
              _loading = false;
            });
          },
          onError: (_) {
            // Best-effort - the history fetch already got something on
            // screen; a listener error just means active orders stop
            // live-updating until the next successful attach (e.g. on
            // resume).
          },
        );
  }

  void _detachActiveListener() {
    _activeSub?.cancel();
    _activeSub = null;
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
      ReadCounter.log('orders_tab:loadMoreHistory', snap.docs.length);

      if (!mounted) return;
      setState(() {
        _recentDocs = [
          ..._recentDocs,
          ...snap.docs.map((d) => _OrderRow(d.id, d.data())),
        ];
        if (snap.docs.isNotEmpty) _lastRecentDoc = snap.docs.last;
        _hasMoreRecent = snap.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // --- Merge / filter -----------------------------------------------------

  List<_OrderRow> get _mergedDocs {
    final Map<String, _OrderRow> byId = {};
    for (final row in _recentDocs) {
      byId[row.id] = row;
    }
    // Active orders are added last so one that's also inside the recent
    // window doesn't get counted/shown twice.
    for (final row in _activeDocs) {
      byId[row.id] = row;
    }
    final List<_OrderRow> merged = byId.values.toList();
    merged.sort((a, b) {
      final ta = a.data['createdAt'];
      final tb = b.data['createdAt'];
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
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 40,
              ),
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

    final List<_OrderRow> allDocs = _mergedDocs;
    final List<_OrderRow> filteredDocs = allDocs.where((row) {
      final data = row.data;
      return _selectedStatus == null ||
          (data['status'] ?? '').toString().toLowerCase() == _selectedStatus;
    }).toList();

    final double total = filteredDocs.fold<double>(0, (sum, row) {
      final data = row.data;
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

                        final data = filteredDocs[index].data;
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
                                                  ? orderItems.first['imageUrl']
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
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  orderItems.length == 1
                                                      ? (orderItems.first['productName']
                                                                as String? ??
                                                            '')
                                                      : '${orderItems.length} items',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (dateLabel.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    dateLabel,
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade500,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (total != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 10,
                                              ),
                                              child: Text(
                                                '₱${total.toString()}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        style: const TextStyle(
          color: primaryGreen,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
