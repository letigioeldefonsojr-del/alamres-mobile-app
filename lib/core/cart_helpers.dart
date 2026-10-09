import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/customer/product_options_sheet.dart';

Future<Set<String>> fetchBestSellingProductIds({int topN = 5}) async {
  final ordersSnapshot = await FirebaseFirestore.instance
      .collection('orders')
      .get();
  final Map<String, int> soldCounts = {};

  for (final doc in ordersSnapshot.docs) {
    final data = doc.data();
    final String? productId = data['productId'] as String?;
    if (productId == null) continue;
    final int amount = (data['amount'] as num?)?.toInt() ?? 0;
    soldCounts[productId] = (soldCounts[productId] ?? 0) + amount;
  }

  final sorted = soldCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sorted.take(topN).map((e) => e.key).toSet();
}

Future<void> seedProductCatalog() async {
  final products = FirebaseFirestore.instance.collection('products');

  await products.doc('lucky_me_pancit_canton').set({
    'name': 'Lucky Me Pancit Canton',
    'price': '₱17.00',
    'available': true,
    'flavors': [
      {'name': 'Red (Chili Mansi)', 'stock': 60, 'available': true},
      {'name': 'Orange (Sweet Style)', 'stock': 45, 'available': true},
      {'name': 'Yellow (Original)', 'stock': 80, 'available': true},
      {'name': 'Green (Kalamansi)', 'stock': 0, 'available': false},
    ],
  });

  await products.doc('555_sardines_tomato_sauce').set({
    'name': '555 Sardines in Tomato Sauce',
    'price': '₱32.00',
    'available': true,
    'stockCount': 180,
    'flavors': <Map<String, dynamic>>[],
  });
}

Future<Map<String, dynamic>> readStockDeduction(
  Transaction txn,
  DocumentReference<Map<String, dynamic>> productRef,
  String? flavorName,
  int amount,
) async {
  final snapshot = await txn.get(productRef);
  final data = snapshot.data();
  if (data == null) {
    throw Exception('This product is no longer available.');
  }

  final flavors =
      (data['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

  if (flavors.isNotEmpty && flavorName != null) {
    final index = flavors.indexWhere((f) => f['name'] == flavorName);
    if (index == -1) {
      throw Exception('$flavorName is no longer available.');
    }
    final int currentStock = (flavors[index]['stock'] as num?)?.toInt() ?? 0;
    if (currentStock < amount) {
      throw Exception('Only $currentStock pcs of $flavorName left.');
    }
    final int newStock = currentStock - amount;
    final updatedFlavors = List<Map<String, dynamic>>.from(flavors);
    updatedFlavors[index] = {
      ...updatedFlavors[index],
      'stock': newStock,
      'available': newStock > 0,
    };
    return {'flavors': updatedFlavors};
  }

  final int currentStock = (data['stockCount'] as num?)?.toInt() ?? 0;
  if (currentStock < amount) {
    throw Exception('Only $currentStock pcs of ${data['name']} left.');
  }
  final int newStock = currentStock - amount;
  return {'stockCount': newStock, 'available': newStock > 0};
}

String cartItemId(String productName, String? flavorName) {
  final key = '$productName-${flavorName ?? 'default'}';
  return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

Future<void> addProductToCart({
  required Map<String, dynamic> product,
  required Map<String, dynamic>? flavor,
  required int amount,
  required double unitPrice,
  // Cached alongside the item so the quantity stepper on the Confirm
  // Order screen can switch to wholesale pricing the instant the amount
  // crosses kWholesaleMinimumQuantity, without a network round-trip - see
  // that screen's _updateAmount(). Null when this product/flavor has no
  // wholesale price set.
  String? wholesalePrice,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception('Not signed in');
  }

  final String? productId = product['id'] as String?;
  final String productName = product['name'] as String? ?? '';
  final String? flavorName = flavor?['name'] as String?;
  final String? flavorImage = flavor?['imageUrl'] as String?;
  final String? imageUrl = (flavorImage != null && flavorImage.isNotEmpty)
      ? flavorImage
      : product['imageUrl'] as String?;
  final String docId = cartItemId(productName, flavorName);

  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('cart')
      .doc(docId);

  await ref.set({
    'productId': productId,
    'productName': productName,
    'imageUrl': imageUrl,
    'flavor': flavorName,
    'unitPrice': unitPrice,
    'wholesalePrice': wholesalePrice,
    'amount': FieldValue.increment(amount),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

void showProductOptions(
  BuildContext context, {
  required Map<String, dynamic> product,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Product options',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, anim1, anim2) {
      return ProductOptionsSheet(product: product);
    },
    transitionBuilder: (context, anim1, anim2, child) {
      final double blur = 8 * anim1.value;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

Future<String?> _editAddressDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 2,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Full address'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(context, text);
          },
          child: const Text(
            'Save',
            style: TextStyle(color: Color(0xFF2E6B3E)),
          ),
        ),
      ],
    ),
  );
}

/// Combines a plain address with an optional landmark into the single
/// string used everywhere a delivery address is picked, stored on an
/// order, or shown to whoever fulfills it - kept in one place so a
/// landmark is treated the same way wherever an address flows through.
String combineAddressAndLandmark(String address, String? landmark) {
  final String trimmedLandmark = landmark?.trim() ?? '';
  if (trimmedLandmark.isEmpty) return address;
  return '$address (Landmark: $trimmedLandmark)';
}

Future<String?> pickDeliveryAddress(
  BuildContext context,
  String currentAddress,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

  final userDoc = await userRef.get();
  String profileAddress = (userDoc.data()?['address'] as String?) ?? '';
  final String profileLandmark =
      (userDoc.data()?['landmark'] as String?) ?? '';

  final addressesSnapshot = await userRef
      .collection('addresses')
      .orderBy('createdAt', descending: true)
      .get();
  final List<Map<String, dynamic>> addresses = addressesSnapshot.docs
      .map((doc) => {'id': doc.id, ...doc.data()})
      .toList();

  if (!context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // If the profile address text happens to match one of the saved
          // custom addresses, only highlight one entry (the specific saved
          // address) so the picker never shows two rows selected at once.
          final bool profileMatchesSavedAddress = addresses.any(
            (a) => (a['address'] as String? ?? '') == profileAddress,
          );
          // What actually gets returned/compared for the Profile Address
          // row - the raw address plus its landmark folded in, so the
          // landmark rides along through the order automatically without
          // needing its own field threaded through the whole checkout
          // flow.
          final String combinedProfileAddress = combineAddressAndLandmark(
            profileAddress,
            profileLandmark,
          );

          Future<void> editProfileAddress() async {
            final updated = await _editAddressDialog(
              context,
              title: 'Edit Profile Address',
              initialValue: profileAddress,
            );
            if (updated == null) return;
            await userRef.set({'address': updated}, SetOptions(merge: true));
            profileAddress = updated;
            setSheetState(() {});
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Choose Delivery Address',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (profileAddress.trim().isNotEmpty)
                      // Built from two independent, side-by-side tap targets
                      // (rather than ListTile's onTap + trailing combo) so
                      // selecting the address and editing it can never
                      // intercept each other's taps.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(
                                  sheetContext,
                                  combinedProfileAddress,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    4,
                                    10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        (currentAddress ==
                                                    combinedProfileAddress &&
                                                !profileMatchesSavedAddress)
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        color: const Color(0xFF2E6B3E),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Profile Address',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              profileAddress,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            if (profileLandmark
                                                .trim()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Landmark: $profileLandmark',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFF2E6B3E),
                            ),
                            tooltip: 'Edit profile address',
                            onPressed: editProfileAddress,
                          ),
                        ],
                      )
                    else
                      ListTile(
                        leading: const Icon(
                          Icons.add_location_alt_outlined,
                          color: Color(0xFF2E6B3E),
                        ),
                        title: const Text('Add Profile Address'),
                        onTap: editProfileAddress,
                      ),
                    if (addresses.isNotEmpty) const Divider(height: 1),
                    ...addresses.map((data) {
                      final String label = data['label'] as String? ?? 'Address';
                      final String address = data['address'] as String? ?? '';
                      final String landmark =
                          data['landmark'] as String? ?? '';
                      final String combinedAddress = combineAddressAndLandmark(
                        address,
                        landmark,
                      );
                      final bool isSelected =
                          currentAddress == combinedAddress;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: const Color(0xFF2E6B3E),
                        ),
                        title: Text(label),
                        subtitle: Text(
                          landmark.trim().isEmpty
                              ? address
                              : '$address\nLandmark: $landmark',
                        ),
                        onTap: () =>
                            Navigator.pop(sheetContext, combinedAddress),
                      );
                    }),
                    const Divider(height: 1),
                    // Managing saved addresses (adding/removing) now lives
                    // only in the Profile section, so this sheet is just
                    // for picking one - no separate "Add New Address" here
                    // to avoid two different places that do the same
                    // thing.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'To add a new address, go to your profile.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
