import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/cart_helpers.dart';
import '../../core/product_helpers.dart';
import '../../core/product_view_preference.dart';
import '../../services/product_repository.dart';
import '../../widgets/cart_floating_bar.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_list_tile.dart';
import '../../widgets/product_view_mode_button.dart';

class CategoryProductsScreen extends StatefulWidget {
  // The display label as derived live elsewhere (categories_tab.dart,
  // home_tab.dart) - this screen normalizes it itself (see
  // normalizeCategoryKey()) rather than requiring callers to pass a
  // separate key, so matching stays case/whitespace-insensitive without
  // threading an extra parameter through every call site.
  final String category;

  const CategoryProductsScreen({super.key, required this.category});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  // The product backend has no field to query a normalized category key
  // server-side (and the admin site's data structure isn't something this
  // app should change), so this screen works off the shared in-memory
  // catalog (ProductRepository) - the same pattern the search boxes
  // elsewhere already use - and filters/derives everything client-side
  // instead of a scoped `where('category', isEqualTo: ...)` query. That's
  // also what makes it possible to tell "this category still exists, just
  // happens to be empty right now" apart from "this category doesn't exist
  // anywhere anymore" for the fallback-to-all-products behavior below.
  //
  // Recomputing a case-insensitive match plus deriveLiveCategories()
  // across 4,500+ products is only worth doing once per actual catalog
  // update, not on every rebuild this screen goes through for unrelated
  // reasons (picking a sort option, etc.) - this cache keys off the
  // product list's own identity so a rebuild with the same data just
  // reuses the last result instead of rescanning everything again.
  List<Map<String, dynamic>>? _lastProducts;
  List<Map<String, dynamic>> _lastAllProducts = const [];
  List<Map<String, dynamic>> _lastMatches = const [];
  bool _lastCategoryStillExists = true;

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
    super.dispose();
  }

  void _recomputeIfNeeded(List<Map<String, dynamic>> data) {
    if (identical(data, _lastProducts)) return;
    _lastProducts = data;
    _lastAllProducts = data;
    final String key = normalizeCategoryKey(widget.category);
    _lastMatches = _lastAllProducts
        .where((p) => productMatchesCategoryKey(p, key))
        .toList();
    _lastCategoryStillExists = deriveLiveCategories(
      _lastAllProducts,
    ).any((c) => c.key == key);
  }

  Future<void> _pickSort() async {
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
                  ...ProductSortOption.values
                      .where((o) => o != ProductSortOption.category)
                      .map((option) {
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
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: ProductRepository.instance.productsNotifier,
      builder: (context, allProducts, _) {
        if (!ProductRepository.instance.hasRefreshedOnce &&
            allProducts.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              title: Text(widget.category),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        _recomputeIfNeeded(allProducts);

        // The category this screen was opened for has no products left
        // anywhere in the catalog anymore (e.g. the admin bulk-deleted
        // every item in it) - rather than leaving the customer stuck on a
        // permanently empty, dead-end screen, fall back to showing every
        // product instead, with a small notice explaining why. A
        // category that still exists but just has 0 products *right now*
        // (nothing was ever added to it, or everything's still loading)
        // keeps the normal empty state below instead.
        final bool fellBackToAll =
            !_lastCategoryStillExists && _lastAllProducts.isNotEmpty;
        final List<Map<String, dynamic>> products = fellBackToAll
            ? _lastAllProducts
            : _lastMatches;
        final sorted = sortProducts(products, _sortOption);

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            title: Text(fellBackToAll ? 'All Products' : widget.category),
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
            children: [
              if (fellBackToAll)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade50,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Text(
                    '"${widget.category}" is no longer available - '
                    'showing all products instead.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              Expanded(
                child: sorted.isEmpty
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
                                  Icons.inventory_2_outlined,
                                  color: primaryGreen,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No products in this category yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ValueListenableBuilder<ProductViewMode>(
                        valueListenable: ProductViewPreference.notifier,
                        builder: (context, viewMode, _) {
                          final bottomPad =
                              20 + MediaQuery.of(context).padding.bottom;

                          if (viewMode == ProductViewMode.list) {
                            return ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                20,
                                20,
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
                                  onTap: () => showProductOptions(
                                    context,
                                    product: product,
                                  ),
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
                              20,
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
                                onImageTap: () => showProductOptions(
                                  context,
                                  product: product,
                                ),
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
      },
    );
  }
}
