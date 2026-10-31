import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/read_counter.dart';

// Was a StatelessWidget that called `cartRef.snapshots()` straight inside
// build() - every time whatever ancestor holds this badge (an AppBar,
// typically) rebuilt for any reason at all, that line ran again and
// handed StreamBuilder a brand-new Stream instance. StreamBuilder treats a
// new stream as a new subscription: it cancels the old one and
// re-subscribes, which re-reads the customer's whole cart from Firestore
// again - on every rebuild, however unrelated to the cart. Now a
// StatefulWidget so the stream itself is created exactly once, in
// initState, and reused across every rebuild - same fix already applied
// to cart_screen.dart's own cart listener, see its _cartStream comment.
class CartBadge extends StatefulWidget {
  // The badge's thin outline - defaults to the app's primary green (matches
  // Home header's green background); pass white when placing this badge
  // over a white background instead, so the ring still blends in.
  final Color borderColor;

  const CartBadge({super.key, this.borderColor = const Color(0xFF2E6B3E)});

  @override
  State<CartBadge> createState() => _CartBadgeState();
}

class _CartBadgeState extends State<CartBadge> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cartStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _cartStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('cart')
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = _cartStream;
    if (stream == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          ReadCounter.log('cart_badge:cart', snapshot.data!.docs.length);
        }
        final int count = snapshot.data?.docs.length ?? 0;

        if (count <= 0) return const SizedBox.shrink();

        final String label = count > 99 ? '99+' : '$count';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: widget.borderColor, width: 1.5),
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
