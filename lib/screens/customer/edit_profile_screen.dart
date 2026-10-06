import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'address_picker_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleInitialController =
      TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();

  // Populated by IntlPhoneField's onChanged - _mobileCountryDialCode is
  // e.g. "+63" and _mobileNationalNumber is the digits after that (no
  // leading 0). Mirrors the same pattern used in register_screen.dart.
  String _mobileCountryDialCode = '+63';
  String _mobileNationalNumber = '';
  // The number as loaded from Firestore (legacy "09XXXXXXXXX" format),
  // used only to pre-populate IntlPhoneField's initialValue.
  String _initialMobileNumber = '';

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
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
      final data = doc.data();
      if (data != null) {
        _firstNameController.text = data['firstName'] ?? '';
        _middleInitialController.text = data['middleInitial'] ?? '';
        _lastNameController.text = data['lastName'] ?? '';
        final String storedMobile = data['mobileNumber'] ?? '';
        // Legacy stored format is "09XXXXXXXXX" - strip the leading 0 so
        // IntlPhoneField's initialValue gets just the 10-digit national
        // number (paired with initialCountryCode: 'PH').
        _initialMobileNumber = storedMobile.startsWith('0')
            ? storedMobile.substring(1)
            : storedMobile;
        _mobileNationalNumber = _initialMobileNumber;
        _addressController.text = data['address'] ?? '';
        _landmarkController.text = data['landmark'] ?? '';
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String firstName = _firstNameController.text.trim();
      final String middleInitial = _middleInitialController.text.trim();
      final String lastName = _lastNameController.text.trim();
      // Built from whichever name parts are actually filled in - some
      // accounts (e.g. signed up with Google) only ever had a single
      // display name, never split into first/middle/last, so any of
      // these can legitimately be blank here.
      final String fullName = [
        firstName,
        if (middleInitial.isNotEmpty) '${middleInitial.replaceAll('.', '')}.',
        lastName,
      ].where((part) => part.isNotEmpty).join(' ');

      // Leave the Firebase Auth display name alone if every name field is
      // blank, rather than wiping out whatever name was already there.
      if (fullName.isNotEmpty) {
        await user.updateDisplayName(fullName);
      }

      final String mobileDigits = _mobileNationalNumber.trim().isEmpty
          ? ''
          : (_mobileCountryDialCode == '+63'
                ? '0$_mobileNationalNumber'
                : '$_mobileCountryDialCode$_mobileNationalNumber');

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'middleInitial': middleInitial,
        'lastName': lastName,
        'fullName': fullName,
        'mobileNumber': mobileDigits,
        'address': _addressController.text.trim(),
        'landmark': _landmarkController.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not save changes. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickAddressOnMap() async {
    final String? picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressPickerScreen(
          initialAddress: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
        ),
      ),
    );
    if (picked != null && picked.trim().isNotEmpty) {
      setState(() => _addressController.text = picked);
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        letterSpacing: 0.5,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('FIRST NAME'),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        // Optional to fill in - showing current info and
                        // editing any single field shouldn't be blocked
                        // by another field that happens to be blank.
                        decoration: _fieldDecoration(
                          'e.g. Zeus Mario',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('MIDDLE INITIAL'),
                      TextFormField(
                        controller: _middleInitialController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 1,
                        decoration: _fieldDecoration(
                          'e.g. D',
                          Icons.person_outline,
                        ).copyWith(counterText: ''),
                      ),
                      const SizedBox(height: 20),
                      _label('LAST NAME'),
                      TextFormField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        // Optional - see FIRST NAME above.
                        decoration: _fieldDecoration(
                          'e.g. Zepp',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('MOBILE NUMBER'),
                      IntlPhoneField(
                        initialCountryCode: 'PH',
                        initialValue: _initialMobileNumber,
                        keyboardType: TextInputType.phone,
                        dropdownIconPosition: IconPosition.trailing,
                        flagsButtonPadding: const EdgeInsets.only(left: 12),
                        decoration: _fieldDecoration(
                          '9XX XXX XXXX',
                          Icons.phone_outlined,
                        ),
                        onChanged: (phone) {
                          _mobileCountryDialCode = phone.countryCode;
                          _mobileNationalNumber = phone.number;
                        },
                        validator: (phone) {
                          // Optional - leave blank rather than block
                          // saving unrelated edits. But if something was
                          // typed, it still has to be a real PH number.
                          if (phone == null || phone.number.trim().isEmpty) {
                            return null;
                          }
                          if (phone.countryCode == '+63' &&
                              phone.number.trim().length != 10) {
                            return 'Enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _label('ADDRESS'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextButton.icon(
                              onPressed: _pickAddressOnMap,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(
                                Icons.map_outlined,
                                size: 16,
                                color: primaryGreen,
                              ),
                              label: const Text(
                                'Pick on Map',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primaryGreen,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _addressController,
                        textCapitalization: TextCapitalization.words,
                        // Optional - see FIRST NAME above.
                        decoration: _fieldDecoration(
                          'House No., Street, Barangay',
                          Icons.location_on_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('LANDMARK'),
                      TextFormField(
                        controller: _landmarkController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _fieldDecoration(
                          'e.g. Near Jollibee, beside the chapel',
                          Icons.push_pin_outlined,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
