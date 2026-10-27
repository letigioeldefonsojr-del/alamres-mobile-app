import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_fly_anchor.dart';
import '../../core/cart_helpers.dart';
import '../../core/constants.dart';
import '../../core/product_helpers.dart';
import '../../widgets/cart_badge.dart';
import '../../widgets/product_card.dart';
import '../../widgets/promo_banner_carousel.dart';
import 'all_products_screen.dart';
import 'cart_screen.dart';
import 'categories_tab.dart';
import 'category_products_screen.dart';
import 'featured_products_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _getDisplayName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim().split(' ').first;
    }
    if (user?.email != null) {
      return user!.email!.split('@').first;
    }
    return 'Guest';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 20,
              24,
              28,
            ),
            decoration: const BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getDisplayName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CartScreen(),
                            ),
                          );
                        },
                        child: SizedBox(
                          key: cartIconKey,
                          width: 44,
                          height: 44,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Center(
                                child: Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              Positioned(top: 2, right: 2, child: CartBadge()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllProductsScreen(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey),
                          SizedBox(width: 10),
                          Text(
                            'Search products...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const PromoBannerCarousel(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Categories',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CategoriesPlaceholderTab(),
                      ),
                    );
                  },
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: primaryGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _LiveCategoryRow(),

          const SizedBox(height: 24),

          // Admin-curated best sellers (the bestSeller field) - a
          // separate list from the order-count badge used elsewhere on
          // this screen. Hidden entirely when nothing qualifies.
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('bestSeller', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];

              // Filtered live, after the stream emits, from whatever the
              // admin flagged as bestSeller - a restock (or a stock-out)
              // just shows up here on its own next snapshot, with no
              // Firestore write of our own.
              final bestSellers = docs
                  .map((doc) => {...doc.data(), 'id': doc.id})
                  .where((product) => !isOutOfStock(product))
                  .toList()
                ..sort(
                  (a, b) => (a['name'] as String? ?? '')
                      .toLowerCase()
                      .compareTo((b['name'] as String? ?? '').toLowerCase()),
                );

              if (bestSellers.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Best Sellers',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 260,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: bestSellers.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final product = bestSellers[index];
                        return SizedBox(
                          width: 150,
                          child: ProductCard(
                            product: product,
                            onImageTap: () => showProductOptions(
                              context,
                              product: product,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),

          // Admin-controlled: a product shows here only while its own
          // Firestore doc has featured == true, ordered by the admin
          // site's featuredAt (most recently featured first, missing
          // dates sorted last). Sorted client-side rather than via
          // .orderBy() so this doesn't depend on a composite index.
          // Entirely hidden when nothing is featured.
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('featured', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];

              // Filtered live, after the stream emits, from whatever the
              // admin flagged as featured - a restock (or a stock-out)
              // just shows up here on its own next snapshot, with no
              // Firestore write of our own.
              final featuredProducts = docs
                  .map((doc) => {...doc.data(), 'id': doc.id})
                  .where((product) => !isOutOfStock(product))
                  .toList()
                ..sort((a, b) {
                  final Timestamp? aTime = a['featuredAt'] as Timestamp?;
                  final Timestamp? bTime = b['featuredAt'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

              if (featuredProducts.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Featured Products',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const FeaturedProductsScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'See all',
                            style: TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 260,
                    child: FutureBuilder<Set<String>>(
                      future: fetchBestSellingProductIds(),
                      builder: (context, bestSellingSnapshot) {
                        final bestSellingIds = bestSellingSnapshot.data ?? {};
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: featuredProducts.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            final product = featuredProducts[index];
                            return SizedBox(
                              width: 150,
                              child: ProductCard(
                                product: product,
                                isBestSelling: bestSellingIds.contains(
                                  product['id'],
                                ),
                                onImageTap: () => showProductOptions(
                                  context,
                                  product: product,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          // Extra clearance (not just the usual 24) so the last row of
          // content never sits behind the chat assistant's floating
          // button - see kFabBottomClearance.
          SizedBox(
            height:
                24 +
                kFabBottomClearance +
                MediaQuery.of(context).padding.bottom,
          ),
        ],
      ),
    );
  }
}

// HomeTab above is a StatelessWidget, but the category row needs to
// listen live and cache its own derived category list between rebuilds
// (see the doc comment on _recomputeIfNeeded below) - pulling it out into
// its own small StatefulWidget keeps that state properly scoped instead
// of forcing the whole HomeTab to become stateful just for this one row.
class _LiveCategoryRow extends StatefulWidget {
  const _LiveCategoryRow();

  @override
  State<_LiveCategoryRow> createState() => _LiveCategoryRowState();
}

class _LiveCategoryRowState extends State<_LiveCategoryRow> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  // Categories aren't a separate collection on the admin side - they're
  // whatever distinct `category` values currently exist across products
  // (see deriveLiveCategories() in product_helpers.dart), which can
  // appear/disappear/get renamed at any time via a bulk CSV import.
  // Deriving that list means scanning every product, so it's only worth
  // doing once per actual Firestore snapshot - this cache keys off the
  // snapshot's own QuerySnapshot identity so an unrelated rebuild (e.g.
  // HomeTab's parent rebuilding for any other reason) just reuses the
  // last result instead of rescanning everything again.
  QuerySnapshot<Map<String, dynamic>>? _lastSnapshot;
  List<LiveCategory> _lastCategories = const [];

  void _recomputeIfNeeded(QuerySnapshot<Map<String, dynamic>>? data) {
    if (identical(data, _lastSnapshot)) return;
    _lastSnapshot = data;
    final products = (data?.docs ?? [])
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
    _lastCategories = deriveLiveCategories(products);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 94);
        }
        _recomputeIfNeeded(snapshot.data);
        final categories = _lastCategories;
        if (categories.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 94,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: categories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final category = categories[index];
              final style = categoryStyleFor(category.label);
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CategoryProductsScreen(category: category.label),
                    ),
                  );
                },
                child: SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: style['color'] as Color,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          style['icon'] as IconData,
                          color: primaryGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        category.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
