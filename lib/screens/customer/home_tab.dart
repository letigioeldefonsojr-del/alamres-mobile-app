import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/banner_helpers.dart';
import '../../core/cart_fly_anchor.dart';
import '../../core/cart_helpers.dart';
import '../../core/constants.dart';
import '../../core/product_helpers.dart';
import '../../widgets/cart_badge.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_image.dart';
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

          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: storeBannerStream(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();

              if (data == null) {
                return const SizedBox.shrink();
              }

              if (!isBannerCurrentlyValid(data)) {
                if ((data['scheduleEnd'] as Timestamp?) != null) {
                  deleteStoreBanner();
                }
                return const SizedBox.shrink();
              }

              final String offer = data['offer'] as String? ?? '';
              final String description = data['description'] as String? ?? '';
              final String? bannerImage = data['imageUrl'] as String?;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onLongPress: () async {
                        await seedProductCatalog();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Product catalog seeded.'),
                            ),
                          );
                        }
                      },
                      child: Container(
                        height: 130,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCEBDD),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: bannerImage != null
                                  ? ProductImage(
                                      imageUrl: bannerImage,
                                      iconSize: 40,
                                      borderRadius: BorderRadius.circular(18),
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.image_outlined,
                                        size: 40,
                                        color: primaryGreen.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                    ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.45),
                                    Colors.transparent,
                                  ],
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              bottom: 16,
                              right: 18,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SPECIAL OFFER',
                                    style: TextStyle(
                                      color: Colors.greenAccent.shade100,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    offer,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
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
                  const SizedBox(height: 24),
                ],
              );
            },
          ),

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
          SizedBox(
            height: 94,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: kProductCategories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final category = kProductCategories[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategoryProductsScreen(
                          category: category['label'] as String,
                        ),
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
                            color: category['color'] as Color,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            category['icon'] as IconData,
                            color: primaryGreen,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          category['label'] as String,
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
          ),

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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
