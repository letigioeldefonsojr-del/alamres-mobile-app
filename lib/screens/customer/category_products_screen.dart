import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/cart_helpers.dart';
import '../../core/product_helpers.dart';
import '../../widgets/product_card.dart';

class CategoryProductsScreen extends StatefulWidget {
  final String category;

  const CategoryProductsScreen({super.key, required this.category});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  ProductSortOption _sortOption = ProductSortOption.nameAsc;

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: Text(widget.category),
        actions: [
          IconButton(
            onPressed: _pickSort,
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: widget.category)
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
            );
          }

          final products = docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
          final sorted = sortProducts(products, _sortOption);

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
    );
  }
}
