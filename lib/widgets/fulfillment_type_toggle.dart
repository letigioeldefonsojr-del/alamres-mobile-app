import 'package:flutter/material.dart';
import '../core/delivery_helpers.dart';

/// Segmented Delivery / Pick Up In Store switch - shared by both order
/// confirmation screens (cart checkout and "Buy Now") so the two always
/// look and behave identically rather than drifting apart over time.
class FulfillmentTypeToggle extends StatelessWidget {
  final bool isPickup;
  final ValueChanged<bool> onChanged;

  const FulfillmentTypeToggle({
    super.key,
    required this.isPickup,
    required this.onChanged,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'Delivery',
              icon: Icons.local_shipping_outlined,
              selected: !isPickup,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Pick Up In Store',
              icon: Icons.storefront_outlined,
              selected: isPickup,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? FulfillmentTypeToggle.primaryGreen
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : Colors.black54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown of real (location-configured) store branches, shown only when
/// "Pick Up In Store" is selected. Filters to branches that actually have
/// a location on file (see kStoreBranches in delivery_helpers.dart) - a
/// customer should never be offered a placeholder branch that isn't open
/// yet, and the list grows automatically the moment a new branch's
/// coordinates are filled in, same as the delivery-fee logic already does.
class PickupBranchDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const PickupBranchDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final List<StoreBranch> branches = kStoreBranches
        .where((b) => b.hasLocation)
        .toList();
    final bool valueIsValid = value != null && branches.any(
      (b) => b.name == value,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valueIsValid ? value : null,
          hint: const Text('Select a branch'),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: branches
              .map(
                (b) => DropdownMenuItem<String>(
                  value: b.name,
                  child: Text(b.name),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
