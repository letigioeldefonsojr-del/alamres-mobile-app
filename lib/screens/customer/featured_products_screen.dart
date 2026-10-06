import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../widgets/product_card.dart';
import 'all_products_screen.dart';

class FeaturedProductsScreen extends StatelessWidget {
  const FeaturedProductsScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Featured Products'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AllProductsScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.grid_view_rounded,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'Browse All',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('featured', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
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
                        Icons.star_border,
                        color: primaryGreen,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '-- No more featured products --',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllProductsScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primaryGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(
                        Icons.grid_view_rounded,
                        color: primaryGreen,
                        size: 18,
                      ),
                      label: const Text(
                        'Browse All Products',
                        style: TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Same ordering as the Home screen's Featured Products section -
          // most recently featured first, missing featuredAt sorted last.
          // Sorted client-side so this doesn't depend on a composite index.
          final products = docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList()
            ..sort((a, b) {
              final Timestamp? aTime = a['featuredAt'] as Timestamp?;
              final Timestamp? bTime = b['featuredAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
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
    );
  }
}
