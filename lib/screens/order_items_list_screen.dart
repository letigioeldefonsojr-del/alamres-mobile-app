import 'package:flutter/material.dart';
import '../widgets/order_item_card.dart';

class OrderItemsListScreen extends StatelessWidget {
  final String orderId;
  final List<Map<String, dynamic>> items;
  final double total;

  const OrderItemsListScreen({
    super.key,
    required this.orderId,
    required this.items,
    required this.total,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: Text(
          'Order #${orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase()}',
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${items.length} ITEMS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            ...items.map((item) => OrderItemCard(item: item)),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ORDER TOTAL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
