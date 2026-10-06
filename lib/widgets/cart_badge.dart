import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CartBadge extends StatelessWidget {
  const CartBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final cartRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cart');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cartRef.snapshots(),
      builder: (context, snapshot) {
        final int count = snapshot.data?.docs.length ?? 0;

        if (count <= 0) return const SizedBox.shrink();

        final String label = count > 99 ? '99+' : '$count';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF2E6B3E), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}
