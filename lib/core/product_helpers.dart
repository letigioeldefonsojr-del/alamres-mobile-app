import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'constants.dart';

enum ProductSortOption {
  nameAsc,
  nameDesc,
  priceLowHigh,
  priceHighLow,
  category,
}

double _extractSortPrice(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map(
          (f) =>
              double.tryParse(
                (f['price'] as String? ?? '').replaceAll(
                  RegExp(r'[^0-9.]'),
                  '',
                ),
              ) ??
              0,
        )
        .where((p) => p > 0)
        .toList();
    if (prices.isNotEmpty) {
      prices.sort();
      return prices.first;
    }
  }
  final raw = (product['price'] as String? ?? '').replaceAll(
    RegExp(r'[^0-9.]'),
    '',
  );
  return double.tryParse(raw) ?? 0;
}

List<Map<String, dynamic>> sortProducts(
  List<Map<String, dynamic>> products,
  ProductSortOption option,
) {
  final sorted = List<Map<String, dynamic>>.from(products);
  switch (option) {
    case ProductSortOption.nameAsc:
      sorted.sort(
        (a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo(
          (b['name'] as String? ?? '').toLowerCase(),
        ),
      );
      break;
    case ProductSortOption.nameDesc:
      sorted.sort(
        (a, b) => (b['name'] as String? ?? '').toLowerCase().compareTo(
          (a['name'] as String? ?? '').toLowerCase(),
        ),
      );
      break;
    case ProductSortOption.priceLowHigh:
      sorted.sort(
        (a, b) => _extractSortPrice(a).compareTo(_extractSortPrice(b)),
      );
      break;
    case ProductSortOption.priceHighLow:
      sorted.sort(
        (a, b) => _extractSortPrice(b).compareTo(_extractSortPrice(a)),
      );
      break;
    case ProductSortOption.category:
      sorted.sort(
        (a, b) => (a['category'] as String? ?? '').toLowerCase().compareTo(
          (b['category'] as String? ?? '').toLowerCase(),
        ),
      );
      break;
  }
  return sorted;
}

String sortOptionLabel(ProductSortOption option) {
  switch (option) {
    case ProductSortOption.nameAsc:
      return 'Name (A-Z)';
    case ProductSortOption.nameDesc:
      return 'Name (Z-A)';
    case ProductSortOption.priceLowHigh:
      return 'Price (Low to High)';
    case ProductSortOption.priceHighLow:
      return 'Price (High to Low)';
    case ProductSortOption.category:
      return 'Category';
  }
}

/// A scheduled discount is active when discountPercent > 0 AND (there's no
/// discountStart or it's already passed) AND (there's no discountEnd or it
/// hasn't passed yet). Either date may be missing on purpose - a missing
/// start means "already started", a missing end means "no end date".
bool isDiscountActive(Map<String, dynamic> product) {
  final percent = product['discountPercent'];
  if (percent == null || percent is! num || percent <= 0) return false;
  final start = product['discountStart'];
  final end = product['discountEnd'];
  final DateTime now = DateTime.now();
  if (start is Timestamp && now.isBefore(start.toDate())) return false;
  if (end is Timestamp && now.isAfter(end.toDate())) return false;
  return true;
}

/// Parses a pre-formatted peso string (e.g. "₱45.00") into a double.
/// Returns null for null/empty/unparseable input so callers can fall back
/// gracefully instead of crashing or showing "null".
double? parsePesoAmount(String? value) {
  if (value == null) return null;
  final String digits = value.replaceAll(RegExp(r'[^0-9.]'), '');
  if (digits.isEmpty) return null;
  return double.tryParse(digits);
}

String _formatPesoAmount(double value) => '₱${value.toStringAsFixed(2)}';

/// Older discounts were applied by rewriting `price` directly and stashing
/// the pre-discount amount in `originalPrice` (on the product, or on the
/// specific variant when [variant] is given). When that's the case the
/// percentage math below must NOT run again - `price`/the variant's price
/// is already the effective, discounted amount.
bool _isLegacyDiscount(
  Map<String, dynamic> product, {
  Map<String, dynamic>? variant,
}) {
  final String? scopedOriginal = (variant ?? product)['originalPrice'] as String?;
  return scopedOriginal != null && scopedOriginal.trim().isNotEmpty;
}

/// Whether a "Discounted -X%" banner should be shown for this product (or,
/// for a variant product, this specific flavor).
bool isDiscountVisible(
  Map<String, dynamic> product, {
  Map<String, dynamic>? variant,
}) {
  if (_isLegacyDiscount(product, variant: variant)) {
    final percent = product['discountPercent'];
    return percent is num && percent > 0;
  }
  return isDiscountActive(product);
}

/// The single source of truth for "what should the customer actually pay
/// for this product/variant right now" - use this everywhere a price is
/// displayed or charged instead of reading `price`/`wholesalePrice` fields
/// and re-deriving a discount separately.
///
/// [regularPrice] is whatever the `price` field currently holds for this
/// product (or, for a variant, that flavor's `price`) - for a legacy
/// discount that field is already the discounted amount, so it's returned
/// unchanged; otherwise the live discountPercent is applied to it.
String effectivePrice(
  Map<String, dynamic> product,
  String regularPrice, {
  Map<String, dynamic>? variant,
}) {
  if (_isLegacyDiscount(product, variant: variant)) return regularPrice;
  if (!isDiscountActive(product)) return regularPrice;
  final double? parsed = parsePesoAmount(regularPrice);
  if (parsed == null) return regularPrice;
  final double percent = (product['discountPercent'] as num).toDouble();
  return _formatPesoAmount(parsed * (100 - percent) / 100);
}

/// The regular (pre-discount) price to show struck-through next to
/// [effectivePrice]'s result - for a legacy discount that's the stashed
/// `originalPrice`, otherwise it's just [regularPrice] itself.
String discountRegularPriceLabel(
  Map<String, dynamic> product,
  String regularPrice, {
  Map<String, dynamic>? variant,
}) {
  if (_isLegacyDiscount(product, variant: variant)) {
    final String? original = (variant ?? product)['originalPrice'] as String?;
    if (original != null && original.trim().isNotEmpty) return original;
  }
  return regularPrice;
}

/// "-{percent}%" text for the discount badge, with trailing zeros dropped
/// (12.5 stays "12.5", 10.0 becomes "10"). Returns null when there's no
/// positive discountPercent to show.
String? discountPercentLabel(Map<String, dynamic> product) {
  final percent = product['discountPercent'];
  if (percent is! num || percent <= 0) return null;
  if (percent == percent.roundToDouble()) return percent.toInt().toString();
  String s = percent.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

String formatDiscountDate(DateTime date) {
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String productPriceLabel(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map((f) {
          final raw = (f['price'] as String? ?? '').replaceAll(
            RegExp(r'[^0-9.]'),
            '',
          );
          return double.tryParse(raw) ?? 0;
        })
        .where((p) => p > 0)
        .toList();
    if (prices.isNotEmpty) {
      prices.sort();
      final low = prices.first;
      final high = prices.last;
      if (low == high) return '₱${low.toStringAsFixed(2)}';
      return 'From ₱${low.toStringAsFixed(2)}';
    }
  }
  return product['price'] as String? ?? '₱0.00';
}

/// Mirrors productPriceLabel() but for the optional wholesale price.
/// Returns null when there's nothing to show - either this product/variant
/// has no wholesalePrice set, or (for variant products) none of the
/// flavors do - so callers can just skip rendering a wholesale line
/// instead of displaying "null" or a misleading "₱0.00".
String? productWholesalePriceLabel(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map((f) {
          final raw = (f['wholesalePrice'] as String? ?? '').replaceAll(
            RegExp(r'[^0-9.]'),
            '',
          );
          return double.tryParse(raw) ?? 0;
        })
        .where((p) => p > 0)
        .toList();
    if (prices.isEmpty) return null;
    prices.sort();
    final low = prices.first;
    final high = prices.last;
    if (low == high) return '₱${low.toStringAsFixed(2)}';
    return 'From ₱${low.toStringAsFixed(2)}';
  }
  final String? raw = product['wholesalePrice'] as String?;
  if (raw == null || raw.trim().isEmpty) return null;
  return raw;
}

/// Used to filter curated home-screen sections (Best Sellers, Featured)
/// live as stock changes - distinct from extractTotalStock()'s simple sum,
/// which just dims a card everywhere else. A variant product only counts
/// as out of stock once every one of its flavors does (or the product
/// itself is explicitly marked unavailable, which overrides every
/// flavor); a simple product is out of stock when explicitly marked
/// unavailable or its stockCount is exactly 0. A missing/non-numeric
/// stockCount with available not explicitly false is treated as in stock.
bool isOutOfStock(Map<String, dynamic> product) {
  final bool productUnavailable = product['available'] == false;

  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    if (productUnavailable) return true;
    return flavors.every((f) {
      final bool flavorUnavailable = f['available'] == false;
      final stock = f['stock'];
      final bool flavorEmpty = stock is num && stock == 0;
      return flavorUnavailable || flavorEmpty;
    });
  }

  if (productUnavailable) return true;
  final stockCount = product['stockCount'];
  return stockCount is num && stockCount == 0;
}

/// Whether this product should show the "Best Seller" badge. Driven
/// entirely by the admin-curated `bestSeller` field on the product
/// document - a missing or non-boolean value is treated as false, per
/// the admin website's own data contract for this field.
bool isBestSeller(Map<String, dynamic> product) {
  final value = product['bestSeller'];
  return value is bool && value;
}

/// True when any flavor (or, for a simple product, the product itself) has
/// a discount that should currently be shown to the customer.
bool productHasVisibleDiscount(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    return flavors.any((f) => isDiscountVisible(product, variant: f));
  }
  return isDiscountVisible(product);
}

/// Mirrors productPriceLabel() but returns the discount-aware price that
/// should be shown prominently (and, for a variant product, the
/// low/"From" price across flavors computed the same discount-aware way).
String effectivePriceLabel(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map((f) {
          final String raw = f['price'] as String? ?? '';
          if (raw.isEmpty) return 0.0;
          return parsePesoAmount(effectivePrice(product, raw, variant: f)) ??
              0;
        })
        .where((p) => p > 0)
        .toList();
    if (prices.isNotEmpty) {
      prices.sort();
      final low = prices.first;
      final high = prices.last;
      if (low == high) return _formatPesoAmount(low);
      return 'From ${_formatPesoAmount(low)}';
    }
  }
  final String regular = product['price'] as String? ?? '₱0.00';
  return effectivePrice(product, regular);
}

/// Mirrors effectivePriceLabel() but for the regular/pre-discount price
/// that should be shown struck-through next to it. Returns null when
/// there's no visible discount to strike through in the first place, so
/// callers can skip rendering the strikethrough price entirely.
String? discountRegularPriceRangeLabel(Map<String, dynamic> product) {
  if (!productHasVisibleDiscount(product)) return null;
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map((f) {
          final String raw = f['price'] as String? ?? '';
          if (raw.isEmpty) return 0.0;
          return parsePesoAmount(
                discountRegularPriceLabel(product, raw, variant: f),
              ) ??
              0;
        })
        .where((p) => p > 0)
        .toList();
    if (prices.isNotEmpty) {
      prices.sort();
      final low = prices.first;
      final high = prices.last;
      if (low == high) return _formatPesoAmount(low);
      return 'From ${_formatPesoAmount(low)}';
    }
  }
  final String regular = product['price'] as String? ?? '₱0.00';
  return discountRegularPriceLabel(product, regular);
}

/// Shared by resolveLiveUnitPrice() (checkout, inside a transaction) and
/// liveUnitPriceFromProductDoc() (cart display, outside a transaction) -
/// given a product document's raw data, works out what the customer
/// should actually be charged for the named flavor (or the product itself
/// when [flavorName] is null) right now. Falls back to [fallbackUnitPrice]
/// if the flavor/price can't be found, e.g. the flavor was removed.
double _effectiveUnitPriceFromData(
  Map<String, dynamic> data,
  String? flavorName,
  double fallbackUnitPrice,
) {
  Map<String, dynamic>? variant;
  String? regularPrice;
  if (flavorName != null) {
    final flavors =
        (data['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final f in flavors) {
      if (f['name'] == flavorName) {
        variant = f;
        break;
      }
    }
    regularPrice = variant?['price'] as String?;
  }
  regularPrice ??= data['price'] as String?;
  if (regularPrice == null || regularPrice.trim().isEmpty) {
    return fallbackUnitPrice;
  }

  final String effective = effectivePrice(data, regularPrice, variant: variant);
  return parsePesoAmount(effective) ?? fallbackUnitPrice;
}

/// Re-reads a product's current price/discount state inside an in-flight
/// Firestore transaction and returns what should actually be charged right
/// now - so if a scheduled discount started or ended while an item sat in
/// the cart, checkout always bills today's price rather than the stale
/// snapshot taken when the item was added. Falls back to
/// [fallbackUnitPrice] if the product (or named flavor) can't be read
/// anymore, e.g. it was deleted since the cart item was added.
Future<double> resolveLiveUnitPrice(
  Transaction txn,
  DocumentReference<Map<String, dynamic>> productRef,
  String? flavorName,
  double fallbackUnitPrice,
) async {
  final snapshot = await txn.get(productRef);
  final data = snapshot.data();
  if (data == null) return fallbackUnitPrice;
  return _effectiveUnitPriceFromData(data, flavorName, fallbackUnitPrice);
}

/// Same price-resolution logic as resolveLiveUnitPrice(), but for a plain
/// product document snapshot rather than one read inside a transaction -
/// meant for live display (e.g. a cart row listening to the product via
/// .snapshots()) rather than for charging at checkout. Falls back to
/// [fallbackUnitPrice] if [productData] is null (the product doc hasn't
/// loaded yet, or no longer exists) or the flavor/price can't be found.
double liveUnitPriceFromProductDoc(
  Map<String, dynamic>? productData,
  String? flavorName,
  double fallbackUnitPrice,
) {
  if (productData == null) return fallbackUnitPrice;
  return _effectiveUnitPriceFromData(productData, flavorName, fallbackUnitPrice);
}

enum StockLevel { critical, low, enough }

StockLevel getStockLevel(int totalStock) {
  if (totalStock <= 10) return StockLevel.critical;
  if (totalStock <= 30) return StockLevel.low;
  return StockLevel.enough;
}

int extractTotalStock(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    return flavors.fold<int>(
      0,
      (sum, f) => sum + ((f['stock'] as num?)?.toInt() ?? 0),
    );
  }
  return (product['stockCount'] as num?)?.toInt() ?? 0;
}

String stockLevelLabel(StockLevel level) {
  switch (level) {
    case StockLevel.critical:
      return 'Critically Low';
    case StockLevel.low:
      return 'Low Stock';
    case StockLevel.enough:
      return 'Enough Stock';
  }
}

Color stockLevelColor(StockLevel level) {
  switch (level) {
    case StockLevel.critical:
      return Colors.redAccent;
    case StockLevel.low:
      return Colors.orange;
    case StockLevel.enough:
      return const Color(0xFF2E6B3E);
  }
}

String productStockLabel(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final int total = flavors.isNotEmpty
      ? flavors.fold<int>(
          0,
          (sum, f) => sum + ((f['stock'] as num?)?.toInt() ?? 0),
        )
      : (product['stockCount'] as num?)?.toInt() ?? 0;
  return '$total pcs available';
}

Future<String?> uploadImageToCloudinary(XFile imageFile) async {
  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/image/upload',
  );
  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = kCloudinaryUploadPreset
    ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['secure_url'] as String?;
  }
  return null;
}

Future<String?> pickAndUploadProductImage(BuildContext context) async {
  final ImageSource? source = await showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add Product Photo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt_outlined,
                    color: Color(0xFF2E6B3E),
                  ),
                  title: const Text('Take Photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF2E6B3E),
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (source == null) return null;

  final ImagePicker picker = ImagePicker();
  final XFile? file = await picker.pickImage(
    source: source,
    imageQuality: 70,
    maxWidth: 1080,
  );

  if (file == null) return null;
  if (!context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        const Center(child: CircularProgressIndicator(color: Colors.white)),
  );

  String? url;
  try {
    url = await uploadImageToCloudinary(file);
  } catch (_) {
    url = null;
  }

  if (context.mounted) {
    Navigator.pop(context);
  }

  if (url == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not upload photo. Please try again.'),
      ),
    );
  }

  return url;
}

Future<void> deleteProduct(String productId) async {
  await FirebaseFirestore.instance
      .collection('products')
      .doc(productId)
      .delete();
}

Future<bool> confirmDeleteProduct(
  BuildContext context,
  String productName,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove Product'),
      content: Text(
        'Are you sure you want to remove "$productName"? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Remove',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}
