import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class _OrdersListViewState extends State<OrdersListView> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  String? _selectedStatus;

  static const List<Map<String, String>> _statusOptions = [
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'approved', 'label': 'Approved'},
    {'value': 'on_the_way', 'label': 'On Its Way'},
    {'value': 'delivered', 'label': 'Delivered'},
    {'value': 'cancelled', 'label': 'Cancelled'},
    {'value': 'undelivered', 'label': 'Unable to Deliver'},
  ];

  Color _statusColor(String status) => orderStatusColor(status);

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

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  bool _isInSelectedMonth(dynamic createdAt) {
    if (createdAt is! Timestamp) return false;
    final d = createdAt.toDate();
    return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(child: Text('Please log in to view your orders.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
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
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];

        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bool monthMatch = _isInSelectedMonth(data['createdAt']);
          final bool statusMatch =
              _selectedStatus == null ||
              (data['status'] ?? '').toString().toLowerCase() ==
                  _selectedStatus;
          return monthMatch && statusMatch;
        }).toList();

        for (final doc in allDocs) {
          checkAndAutoConfirmOrder(doc.id, doc.data() as Map<String, dynamic>);
        }

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
                      Row(
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              Icons.chevron_left,
                              color: primaryGreen,
                            ),
                            onPressed: () => _changeMonth(-1),
                          ),
                          Expanded(
                            child: Text(
                              _monthLabel(_selectedMonth),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              Icons.chevron_right,
                              color: primaryGreen,
                            ),
                            onPressed: () => _changeMonth(1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final double monthTotal = filteredDocs.fold<double>(
                            0,
                            (sum, doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final String docStatus = (data['status'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              if (docStatus == 'cancelled' ||
                                  docStatus == 'rejected' ||
                                  docStatus == 'undelivered') {
                                return sum;
                              }
                              final total = data['total'];
                              return sum +
                                  ((total is num) ? total.toDouble() : 0);
                            },
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total this month',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12.5,
                                  ),
                                ),
                                Text(
                                  '₱${monthTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
                child: filteredDocs.isEmpty
                    ? Center(
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
                                  Icons.receipt_long_outlined,
                                  color: primaryGreen,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                allDocs.isEmpty
                                    ? 'No orders yet'
                                    : 'No orders in ${_monthLabel(_selectedMonth)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                allDocs.isEmpty
                                    ? 'Your order history will appear here.'
                                    : 'Try a different month.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          20 + MediaQuery.of(context).padding.bottom,
                        ),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final data =
                              filteredDocs[index].data()
                                  as Map<String, dynamic>;
                          final orderItems = getOrderItems(data);
                          final status = (data['status'] ?? 'pending')
                              .toString();
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
                                                orderStatusLabel(status),
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
            ],
          ),
        );
      },
    );
  }
}
