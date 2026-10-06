import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:csv/csv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/dialog_helpers.dart';
import '../../core/routing.dart';
import '../../services/onesignal_service.dart';
import '../../widgets/profile_menu_tile.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'orders_tab.dart';
import 'saved_addresses_screen.dart';
import 'terms_conditions_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isProcessing = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadMobileNumber();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Stream<Map<String, int>> _orderStatsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.value({'total': 0, 'delivered': 0, 'pending': 0});
    }

    return FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          int total = snapshot.docs.length;
          int delivered = 0;
          int pending = 0;
          for (final doc in snapshot.docs) {
            final status = (doc.data()['status'] ?? '')
                .toString()
                .toLowerCase();
            if (status == 'delivered') delivered++;
            if (status == 'pending') pending++;
          }
          return {'total': total, 'delivered': delivered, 'pending': pending};
        });
  }

  String get _displayName {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!;
    }
    return user?.email?.split('@').first ?? 'Guest';
  }

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

  String? _mobileNumber;

  Future<void> _loadMobileNumber() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final number = doc.data()?['mobileNumber'] as String?;
      if (mounted && number != null && number.trim().isNotEmpty) {
        setState(() => _mobileNumber = number);
      }
    } catch (_) {}
  }

  String get _phone => _mobileNumber ?? '';
  String get _initials {
    final parts = _displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: primaryGreen)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Detach this device from the account before signing out, so a
    // shared/reused device doesn't keep receiving pushes meant for
    // whoever was just signed in. Same fire-and-forget-with-timeout
    // pattern as OneSignal.login() at sign-in - never let a slow or
    // unreachable OneSignal call hold up logging out.
    unawaited(
      OneSignalService.instance.logout().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      ),
    );

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      fadeSlideRoute(const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all associated data. '
          'This action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete Account',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Google-signed-in accounts have no password to confirm with - Firebase
    // still requires a *recent* login before it'll let you delete an
    // account, so re-run the Google picker instead of prompting for a
    // password that doesn't exist for this account.
    final bool signedInWithGoogle = user.providerData.any(
      (info) => info.providerId == GoogleAuthProvider.PROVIDER_ID,
    );

    AuthCredential? credential;

    if (signedInWithGoogle) {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // Cancelled the account picker.
      final googleAuth = await googleUser.authentication;
      credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
    } else {
      if (!mounted) return;
      final String? password = await promptPasswordConfirmation(context);
      if (password == null || password.isEmpty) return;
      if (user.email == null) return;
      credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
    }

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      await user.reauthenticateWithCredential(credential);

      // Same reasoning as _logout() above - detach this device from the
      // account that's about to no longer exist.
      unawaited(
        OneSignalService.instance.logout().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        ),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();
      await user.delete();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(
          const LoginScreen(snackBarMessage: 'Account deleted successfully.'),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = 'Could not delete account. Please try again.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = signedInWithGoogle
            ? 'Could not confirm your Google account. Account was not deleted.'
            : 'Incorrect password. Account was not deleted.';
      } else if (e.code == 'user-mismatch') {
        message =
            'That was a different Google account. Please pick the same '
            'one you\'re signed in with.';
      } else if (e.code == 'requires-recent-login') {
        message =
            'For security, please log out and log back in before deleting your account.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
              20,
              MediaQuery.of(context).padding.top + 24,
              20,
              40,
            ),
            decoration: const BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                      if (_phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _phone,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditProfileScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: StreamBuilder<Map<String, int>>(
                  stream: _orderStatsStream(),
                  builder: (context, snapshot) {
                    final stats =
                        snapshot.data ??
                        const {'total': 0, 'delivered': 0, 'pending': 0};
                    return Row(
                      children: [
                        Expanded(
                          child: _StatItem(
                            value: '${stats['total']}',
                            label: 'Orders',
                          ),
                        ),
                        _StatDivider(),
                        Expanded(
                          child: _StatItem(
                            value: '${stats['delivered']}',
                            label: 'Delivered',
                          ),
                        ),
                        _StatDivider(),
                        Expanded(
                          child: _StatItem(
                            value: '${stats['pending']}',
                            label: 'Pending',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ProfileMenuTile(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    subtitle: 'Update your personal info',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditProfileScreen(),
                        ),
                      );
                      await _loadMobileNumber();
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.local_shipping_outlined,
                    label: 'My Orders',
                    subtitle: 'View order history',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MyOrdersScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    subtitle: 'Manage alerts & updates',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.location_on_outlined,
                    label: 'Saved Addresses',
                    subtitle: 'Manage delivery addresses',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SavedAddressesScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.description_outlined,
                    label: 'Terms & Conditions',
                    subtitle: 'Read our terms',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TermsConditionsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _logout,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            label: const Text(
                              'Logout',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _deleteAccount,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              'Delete Account',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Almares 328 v$_appVersion - Wholesale Grocery & Sari-Sari Store',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                  const SizedBox(height: 12),

                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: const Color(0xFFEFEFEF));
  }
}
