import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isLoading = true;
  bool _orderUpdates = true;
  bool _promotions = true;
  bool _appUpdates = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final prefs = doc.data()?['notificationPrefs'] as Map<String, dynamic>?;
      if (prefs != null) {
        _orderUpdates = prefs['orderUpdates'] ?? true;
        _promotions = prefs['promotions'] ?? true;
        _appUpdates = prefs['appUpdates'] ?? false;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notificationPrefs': {
        'orderUpdates': _orderUpdates,
        'promotions': _promotions,
        'appUpdates': _appUpdates,
      },
    }, SetOptions(merge: true));
  }

  Widget _buildFuturePreference({
    required String title,
    required String subtitle,
    required bool value,
  }) {
    return Opacity(
      opacity: 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: const Text(
                  'This feature is coming in a future update.',
                ),
                backgroundColor: Colors.grey.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
        },
        child: AbsorbPointer(
          child: SwitchListTile(
            activeThumbColor: primaryGreen,
            title: Text(title),
            subtitle: Text(subtitle),
            value: value,
            onChanged: (v) {},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SwitchListTile(
                  activeThumbColor: primaryGreen,
                  title: const Text('Order Updates'),
                  subtitle: const Text('Get notified about your order status'),
                  value: _orderUpdates,
                  onChanged: (v) {
                    setState(() => _orderUpdates = v);
                    _save();
                  },
                ),
                _buildFuturePreference(
                  title: 'Promotions & Offers',
                  subtitle: 'Deals, discounts, and special offers',
                  value: _promotions,
                ),
                _buildFuturePreference(
                  title: 'App Updates',
                  subtitle: 'News about new features',
                  value: _appUpdates,
                ),
              ],
            ),
    );
  }
}
