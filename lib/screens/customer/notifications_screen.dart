import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/onesignal_service.dart';
import '../../services/engagement_reminder_service.dart';

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
  bool _shopReminders = false;

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
        _shopReminders = prefs['shopReminders'] ?? false;
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
        'shopReminders': _shopReminders,
      },
    }, SetOptions(merge: true));
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
                SwitchListTile(
                  activeThumbColor: primaryGreen,
                  title: const Text('Promotions & Offers'),
                  subtitle: const Text('Deals, discounts, and special offers'),
                  value: _promotions,
                  onChanged: (v) {
                    setState(() => _promotions = v);
                    _save();
                    // Keeps OneSignal's tag in sync immediately, instead of
                    // waiting for the next login, so a promo push sent
                    // right after toggling this off doesn't still reach
                    // this device.
                    OneSignalService.instance.setPromotionsTag(v);
                  },
                ),
                SwitchListTile(
                  activeThumbColor: primaryGreen,
                  title: const Text('App Updates'),
                  subtitle: const Text('News about new features'),
                  value: _appUpdates,
                  onChanged: (v) {
                    setState(() => _appUpdates = v);
                    _save();
                  },
                ),
                SwitchListTile(
                  activeThumbColor: primaryGreen,
                  title: const Text('Shop Reminders'),
                  subtitle: const Text(
                    'Occasional nudges to check out Almares 328 - works even when the app is closed',
                  ),
                  value: _shopReminders,
                  onChanged: (v) {
                    setState(() => _shopReminders = v);
                    _save();
                    // Reschedules (or cancels) the on-device reminders right
                    // away, same reasoning as the promotions tag above.
                    EngagementReminderService.instance.applyPreference(v);
                  },
                ),
              ],
            ),
    );
  }
}
