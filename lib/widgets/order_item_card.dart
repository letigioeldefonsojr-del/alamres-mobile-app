import 'package:flutter/material.dart';
import 'product_image.dart';

class OrderItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  // Pass both to make the item's quantity editable; leave null (the
  // default, used for past-order history) to show a plain read-only "x2".
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  const OrderItemCard({
    super.key,
    required this.item,
    this.onIncrement,
    this.onDecrement,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final String name = item['productName'] as String? ?? '';
    final String? flavor = item['flavor'] as String?;
    final int amount = (item['amount'] as num?)?.toInt() ?? 0;
    final double unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
    final double subtotal =
        (item['subtotal'] as num?)?.toDouble() ?? (unitPrice * amount);
    final bool editable = onIncrement != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ProductImage(
              imageUrl: item['imageUrl'] as String?,
              seedText: name,
              iconSize: 24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${unitPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (flavor != null && flavor.isNotEmpty) ? flavor : ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    editable
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QtyButton(
                                icon: Icons.remove,
                                onTap: onDecrement,
                              ),
                              SizedBox(
                                width: 26,
                                child: Text(
                                  '$amount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              _QtyButton(icon: Icons.add, onTap: onIncrement),
                            ],
                          )
                        : Text(
                            'x$amount',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₱${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({required this.icon, required this.onTap});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Material(
      color: primaryGreen.withValues(alpha: enabled ? 0.1 : 0.04),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            icon,
            color: enabled ? primaryGreen : primaryGreen.withValues(alpha: 0.35),
            size: 13,
          ),
        ),
      ),
    );
  }
}
