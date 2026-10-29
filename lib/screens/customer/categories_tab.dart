import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/cart_helpers.dart';
import '../../core/constants.dart';
import '../../core/product_helpers.dart';
import '../../core/product_view_preference.dart';
import '../../core/search_helpers.dart';
import '../../services/product_repository.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_list_tile.dart';
import '../../widgets/product_view_mode_button.dart';
import 'all_products_screen.dart';
import 'category_products_screen.dart';

class CategoriesPlaceholderTab extends StatefulWidget {
  const CategoriesPlaceholderTab({super.key});

  @override
  State<CategoriesPlaceholderTab> createState() =>
      _CategoriesPlaceholderTabState();
}

class _CategoriesPlaceholderTabState extends State<CategoriesPlaceholderTab> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  // Categories aren't a separate collection on the admin side - they're
  // whatever distinct `category` values currently exist across products,
  // which can appear/disappear/get renamed at any time via a bulk CSV
  // import. Deriving that list (deriveLiveCategories()) means scanning
  // every product, so it's only worth doing once per actual catalog
  // update rather than on every rebuild this screen goes through for
  // unrelated reasons (typing in the search box, picking a sort option) -
  // this cache keys off the product list's own identity so an unrelated
  // rebuild just reuses the last result.
  List<Map<String, dynamic>>? _lastProducts;
  List<Map<String, dynamic>> _lastAllProducts = const [];
  List<LiveCategory> _lastCategories = const [];

  void _recomputeIfNeeded(List<Map<String, dynamic>> data) {
    if (identical(data, _lastProducts)) return;
    _lastProducts = data;
    _lastAllProducts = data;
    _lastCategories = deriveLiveCategories(_lastAllProducts);
  }

  @override
  void initState() {
    super.initState();
    // Keeps the shared catalog's ~3-minute background refresh running while
    // this tab is on screen - see product_repository.dart.
    ProductRepository.instance.registerVisible();
  }

  @override
  void dispose() {
    ProductRepository.instance.unregisterVisible();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSort() async {
    // Without this, if the search field still technically has focus (e.g.
    // the customer tapped it, then tapped Sort without typing anything),
    // Flutter's FocusScope remembers that and restores it - silently
    // reopening the keyboard - the moment this bottom sheet is dismissed.
    // Same reasoning everywhere else in this file that pushes a route or
    // opens a sheet/dialog while the search field is on screen.
    FocusScope.of(context).unfocus();
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
    final bool isSearching = _query.trim().isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Categories',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickSort,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
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
                              Icons.sort,
                              color: primaryGreen,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sortOptionLabel(_sortOption),
                              style: const TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Only shown while searching - this toggle affects the
                    // product grid/list below, and the category tiles
                    // (shown when not searching) aren't a product grid in
                    // that sense, so the button has nothing to do there.
                    if (isSearching)
                      ProductViewModeButton(color: primaryGreen),
                    const SizedBox(width: 4),
                    CartIconButton(
                      color: primaryGreen,
                      badgeBorderColor: Colors.white,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: isSearching
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
              const SizedBox(height: 12),
              if (!isSearching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Material(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        // See _pickSort's comment above - same fix, same
                        // reason: otherwise the search field's keyboard can
                        // reopen by itself when the customer comes back.
                        FocusScope.of(context).unfocus();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllProductsScreen(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.grid_view_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Browse All Products',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'See everything in one place',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ],
                        ),
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
                    _recomputeIfNeeded(products);

                    if (isSearching) {
                      final matches = _lastAllProducts
                          .where(
                            (p) => fuzzyMatches(
                              _query,
                              p['name'] as String? ?? '',
                            ),
                          )
                          .toList();
                      final sorted = sortProducts(matches, _sortOption);

                      if (sorted.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  color: Colors.grey.shade400,
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No products found for "$_query"',
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

                      return ValueListenableBuilder<ProductViewMode>(
                        valueListenable: ProductViewPreference.notifier,
                        builder: (context, viewMode, _) {
                          final bottomPad =
                              20 +
                              kFabBottomClearance +
                              MediaQuery.of(context).padding.bottom;

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
                                  onTap: () {
                                    // See _pickSort's comment above - same
                                    // fix, same reason.
                                    FocusScope.of(context).unfocus();
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
                                onImageTap: () {
                                  // See _pickSort's comment above - same
                                  // fix, same reason.
                                  FocusScope.of(context).unfocus();
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
                    }

                    // Categories aren't a fixed list anymore - this is
                    // whatever deriveLiveCategories() found across the
                    // current product snapshot (cached above), so a
                    // category with zero products left just isn't in
                    // here, and a brand-new one from a CSV import shows
                    // up the moment this stream re-emits.
                    final categories = _lastCategories;

                    if (categories.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.category_outlined,
                                color: Colors.grey.shade400,
                                size: 40,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No categories available yet',
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

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        20 +
                            kFabBottomClearance +
                            MediaQuery.of(context).padding.bottom,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 1.3,
                          ),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final style = categoryStyleFor(category.label);
                        return Material(
                          color: style['color'] as Color,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              // See _pickSort's comment above - this is the
                              // exact "enter a category, exit, keyboard pops
                              // up" case: the search field above can still
                              // have focus even though it's empty and the
                              // category grid (not search results) is what's
                              // showing.
                              FocusScope.of(context).unfocus();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CategoryProductsScreen(
                                    category: category.label,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    style['icon'] as IconData,
                                    color: primaryGreen,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    category.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
