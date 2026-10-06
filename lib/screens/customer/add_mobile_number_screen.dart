import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Mandatory gate screen shown when the signed-in customer's account has
/// no mobile number on file (this happens for accounts created through
/// Google Sign-In, which don't collect a phone number up front). The
/// customer cannot dismiss this screen or navigate away until they save
/// a valid mobile number - there is deliberately no back button and the
/// system back gesture is blocked.
class AddMobileNumberScreen extends StatefulWidget {
  const AddMobileNumberScreen({super.key});

  @override
  State<AddMobileNumberScreen> createState() => _AddMobileNumberScreenState();
}

class _AddMobileNumberScreenState extends State<AddMobileNumberScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();

  String _countryDialCode = '+63';
  String _nationalNumber = '';

  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final String mobileDigits = _countryDialCode == '+63'
          ? '0$_nationalNumber'
          : '$_countryDialCode$_nationalNumber';

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'You are not signed in. Please log in again.';
        });
        return;
      }

      // A mobile number must map to exactly one account, same rule as
      // registration - otherwise phone-number login could pick the
      // wrong account.
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('mobileNumber', isEqualTo: mobileDigits)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty &&
          existing.docs.first.id != user.uid) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'An account already exists for that mobile number.';
        });
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'mobileNumber': mobileDigits}, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not save your mobile number: $e';
      });
    }
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // This screen is mandatory - block the system back gesture/button
      // entirely so the customer can't get around it without saving a
      // valid mobile number.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.phone_iphone,
                    color: primaryGreen,
                    size: 48,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'One Last Step',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'We need a mobile number on file for your account so we '
                    'can reach you about your orders. Please add one to '
                    'continue.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'MOBILE NUMBER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IntlPhoneField(
                    initialCountryCode: 'PH',
                    keyboardType: TextInputType.phone,
                    dropdownIconPosition: IconPosition.trailing,
                    flagsButtonPadding: const EdgeInsets.only(left: 12),
                    decoration: _fieldDecoration(hint: '9XX XXX XXXX'),
                    onChanged: (phone) {
                      _countryDialCode = phone.countryCode;
                      _nationalNumber = phone.number;
                    },
                    validator: (phone) {
                      if (phone == null || phone.number.trim().isEmpty) {
                        return 'Mobile number is required';
                      }
                      if (phone.countryCode == '+63' &&
                          phone.number.trim().length != 10) {
                        return 'Enter a valid 10-digit mobile number';
                      }
                      return null;
                    },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Save and Continue',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
