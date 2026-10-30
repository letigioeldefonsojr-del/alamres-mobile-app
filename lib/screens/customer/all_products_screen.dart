import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/cart_helpers.dart';
import '../../core/focus_helpers.dart';
import '../../core/product_helpers.dart';
import '../../core/search_helpers.dart';
import '../../core/product_view_preference.dart';
import '../../services/product_repository.dart';
import '../../widgets/cart_floating_bar.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_list_tile.dart';
import '../../widgets/product_view_mode_button.dart';

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  @override
  void initState() {
    super.initState();
    // Keeps the shared catalog's ~3-minute background refresh running while
    // this screen is on screen - see product_repository.dart.
    ProductRepository.instance.registerVisible();
  }

  @override
  void dispose() {
    ProductRepository.instance.unregisterVisible();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSort() async {
    // See clearKeyboardFocus's doc comment - without this, if the search
    // field still technically has focus (e.g. the customer tapped it, then
    // tapped Sort without typing anything), the keyboard can reopen by
    // itself the moment this bottom sheet is dismissed. Same reasoning
    // everywhere else in this file that opens a sheet while the search
    // field is on screen.
    clearKeyboardFocus(context);
    final selected = await showModalBottomSheet<ProductSortOption>(
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
                      'Sort By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...ProductSortOption.values.map((option) {
                    final bool isSelected = _sortOption == option;
                    return ListTile(
                      title: Text(sortOptionLabel(option)),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: primaryGreen)
                          : null,
                      onTap: () => Navigator.pop(context, option),
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
    if (selected != null) setState(() => _sortOption = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('All Products'),
        actions: [
          IconButton(
            onPressed: _pickSort,
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
          ),
          const ProductViewModeButton(color: Colors.white),
          const CartIconButton(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search all products...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: ProductRepository.instance.productsNotifier,
              builder: (context, products, _) {
                if (!ProductRepository.instance.hasRefreshedOnce &&
                    products.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final filtered = _query.trim().isEmpty
                    ? products
                    : products
                          .where(
                            (p) => fuzzyMatches(
                              _query,
                              p['name'] as String? ?? '',
                            ),
                          )
                          .toList();

                final sorted = sortProducts(filtered, _sortOption);

                if (sorted.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _query.isEmpty
                                ? Icons.inventory_2_outlined
                                : Icons.search_off,
                            color: primaryGreen.withValues(alpha: 0.4),
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'No products available yet'
                                : 'No products found for "$_query"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return FutureBuilder<Set<String>>(
                  future: fetchBestSellingProductIds(),
                  builder: (context, bestSellingSnapshot) {
                    final bestSellingIds = bestSellingSnapshot.data ?? {};
                    return ValueListenableBuilder<ProductViewMode>(
                      valueListenable: ProductViewPreference.notifier,
                      builder: (context, viewMode, _) {
                        final bottomPad =
                            20 + MediaQuery.of(context).padding.bottom;

                        if (viewMode == ProductViewMode.list) {
                          return ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              0,
                              20,
                              bottomPad,
                            ),
                            itemCount: sorted.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final product = sorted[index];
                              return ProductListTile(
                                product: product,
                                isBestSelling: bestSellingIds.contains(
                                  product['id'],
                                ),
                                onTap: () {
                                  // See _pickSort's comment above - same
                                  // fix, same reason.
                                  clearKeyboardFocus(context);
                                  showProductOptions(
                                    context,
                                    product: product,
                                  );
                                },
                              );
                            },
                          );
                        }

                        final int crossAxisCount =
                            viewMode == ProductViewMode.grid3 ? 3 : 2;
                        final double childAspectRatio =
                            viewMode == ProductViewMode.grid3 ? 0.68 : 0.62;

                        return GridView.builder(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            bottomPad,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: childAspectRatio,
                              ),
                          itemCount: sorted.length,
                          itemBuilder: (context, index) {
                            final product = sorted[index];
                            return ProductCard(
                              product: product,
                              isBestSelling: bestSellingIds.contains(
                                product['id'],
                              ),
                              onImageTap: () {
                                // See _pickSort's comment above - same fix,
                                // same reason.
                                clearKeyboardFocus(context);
                                showProductOptions(
                                  context,
                                  product: product,
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CartFloatingBar(),
    );
  }
}
