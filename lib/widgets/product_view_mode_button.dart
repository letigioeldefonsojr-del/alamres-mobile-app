import 'package:flutter/material.dart';
import '../core/product_view_preference.dart';

/// The same control on every product grid screen for switching between
/// list / 2-column / 3-column - selecting one here updates
/// ProductViewPreference.notifier, which every other product listing
/// screen is also listening to, so the choice applies everywhere at once
/// and is remembered the next time the app opens.
class ProductViewModeButton extends StatelessWidget {
  final Color? color;

  const ProductViewModeButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProductViewMode>(
      valueListenable: ProductViewPreference.notifier,
      builder: (context, mode, _) {
        return PopupMenuButton<ProductViewMode>(
          icon: Icon(mode.icon, color: color),
          tooltip: 'Change view',
          onSelected: ProductViewPreference.set,
          itemBuilder: (context) => ProductViewMode.values.map((m) {
            final bool selected = m == mode;
            return PopupMenuItem<ProductViewMode>(
              value: m,
              child: Row(
                children: [
                  Icon(
                    m.icon,
                    size: 18,
                    color: selected
                        ? const Color(0xFF2E6B3E)
                        : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    m.label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF2E6B3E)
                          : Colors.black87,
                    ),
                  ),
                  if (selected) ...[
                    const Spacer(),
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: Color(0xFF2E6B3E),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
