import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/read_counter.dart';
import '../../core/routing.dart';
import '../../core/validators.dart';
import '../../core/ph_locations.dart';
import '../../services/login_guard_api.dart';
import 'address_picker_screen.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleInitialController =
      TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  // Populated by IntlPhoneField's onChanged - _mobileCountryDialCode is
  // e.g. "+63" and _mobileNationalNumber is the digits after that (no
  // leading 0), matching how the field itself splits them.
  String _mobileCountryDialCode = '+63';
  String _mobileNationalNumber = '';
  // House/Lot No., Street, and Purok stay fully manual - there's no
  // bundled dataset for those. Region/Province/City-Municipality/Barangay
  // are picked from the bundled PSGC dataset instead (see below), so
  // there's never a mismatched or misspelled barangay name.
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _purokController = TextEditingController();
  // Exact coordinates from the last "Pick on Map" selection - the basis
  // for the delivery fee and the pin shown in the admin. Deliberately
  // independent of the address fields above: picking a location never
  // overwrites what's typed, and editing those fields afterward never
  // invalidates the pin already attached.
  double? _addressLat;
  double? _addressLng;
  bool get _hasAddressPin => _addressLat != null && _addressLng != null;

  // The bundled Region/Province/City-Municipality/Barangay dataset, plus
  // whichever of the four the customer has picked so far. Each level is
  // only enabled once its parent is chosen, and choosing a new value at
  // one level clears everything picked below it (see _pickRegion etc.).
  PhLocationsData? _phLocations;
  String? _regionCode;
  String? _regionName;
  String? _provinceCode;
  String? _provinceName;
  String? _municipalityCode;
  String? _municipalityName;
  String? _barangayCode;
  String? _barangayName;
  bool get _hasBarangaySelected => _barangayCode != null;

  // The address fields combined into the single string stored as
  // 'address' and used everywhere else in the app (orders, the admin
  // website, the chatbot) that expects one address line.
  String get _combinedAddressText {
    final String houseNo = _houseNoController.text.trim();
    final String street = _streetController.text.trim();
    final String purok = _purokController.text.trim();
    final parts = <String>[
      if (houseNo.isNotEmpty) houseNo,
      if (street.isNotEmpty) street,
      if (purok.isNotEmpty) 'Purok $purok',
      if (_barangayName != null) 'Barangay $_barangayName',
      if (_municipalityName != null) _municipalityName!,
      if (_provinceName != null) _provinceName!,
    ];
    return parts.join(', ');
  }
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;
  // Shown as a persistent banner (not just a snackbar that can be missed
  // or dismissed) so the exact reason registration failed is always
  // visible on screen until the next attempt.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPhLocationsData();
  }

  // Set only if the dataset genuinely failed to load (e.g. the asset
  // isn't in the build yet) - lets the Region field show what actually
  // happened and offer a retry, instead of sitting on "Loading
  // regions..." forever with no way to tell a real failure apart from
  // one that's just slow.
  String? _phLocationsError;

  Future<void> _loadPhLocationsData() async {
    setState(() => _phLocationsError = null);
    try {
      final PhLocationsData data = await PhLocations.load();
      if (mounted) setState(() => _phLocations = data);
    } catch (e) {
      if (mounted) setState(() => _phLocationsError = e.toString());
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _houseNoController.dispose();
    _streetController.dispose();
    _purokController.dispose();
    _landmarkController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  // Small sub-label for each of the four address fields, nested under
  // the ADDRESS section header - lighter weight than the main
  // field labels (FIRST NAME, MOBILE NUMBER, etc.) so the grouping
  // reads clearly as one section.
  Widget _addressSubLabel(String text, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Text(
            '(optional)',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
          ),
        ],
      ],
    ),
  );

  Future<void> _pickRegion() async {
    final PhLocationsData? data = _phLocations;
    if (data == null) return;
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select Region',
      items: data.regions,
    );
    if (picked == null) return;
    setState(() {
      _regionCode = picked.code;
      _regionName = picked.name;
      // Picking a new region invalidates whatever was picked below it -
      // a province from the old region doesn't belong under the new one.
      _provinceCode = null;
      _provinceName = null;
      _municipalityCode = null;
      _municipalityName = null;
      _barangayCode = null;
      _barangayName = null;
    });
  }

  Future<void> _pickProvince() async {
    final PhLocationsData? data = _phLocations;
    if (data == null || _regionCode == null) return;
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select Province',
      items: data.provincesOf(_regionCode),
    );
    if (picked == null) return;
    setState(() {
      _provinceCode = picked.code;
      _provinceName = picked.name;
      _municipalityCode = null;
      _municipalityName = null;
      _barangayCode = null;
      _barangayName = null;
    });
  }

  Future<void> _pickMunicipality() async {
    final PhLocationsData? data = _phLocations;
    if (data == null || _provinceCode == null) return;
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select City/Municipality',
      items: data.municipalitiesOf(_provinceCode),
    );
    if (picked == null) return;
    setState(() {
      _municipalityCode = picked.code;
      _municipalityName = picked.name;
      _barangayCode = null;
      _barangayName = null;
    });
    // Barangays are the bulk of the dataset and are only parsed on first
    // use - kick that off now, in the background, so it's usually ready
    // by the time the customer actually taps "Select Barangay" below.
    data.prefetchBarangays();
  }

  bool _isLoadingBarangays = false;

  Future<void> _pickBarangay() async {
    final PhLocationsData? data = _phLocations;
    if (data == null || _municipalityCode == null) return;
    setState(() => _isLoadingBarangays = true);
    final List<PhLocationItem> items = await data.barangaysOf(
      _municipalityCode,
    );
    if (!mounted) return;
    setState(() => _isLoadingBarangays = false);
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select Barangay',
      items: items,
    );
    if (picked == null) return;
    setState(() {
      _barangayCode = picked.code;
      _barangayName = picked.name;
    });
  }

  Future<void> _pickAddressOnMap() async {
    final PickedAddress? picked = await Navigator.push<PickedAddress>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressPickerScreen(
          initialAddress: _combinedAddressText.isEmpty
              ? null
              : _combinedAddressText,
        ),
      ),
    );
    if (picked != null) {
      // Only the coordinate is used - with four separate fields there's
      // no single text box to usefully prefill from the map's
      // reverse-geocoded label, so picking a location never touches
      // anything the customer typed.
      setState(() {
        _addressLat = picked.lat;
        _addressLng = picked.lng;
      });
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'mobile-already-in-use':
        return 'An account already exists for that mobile number.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      default:
        // Fall back to whatever Firebase actually says rather than a
        // generic message - that's the difference between "try again"
        // and knowing exactly what to fix.
        return (e.message != null && e.message!.isNotEmpty)
            ? 'Could not create account: ${e.message}'
            : 'Could not create account (${e.code}). Please try again.';
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Not one of the fields' own validators - the region/province/
    // city-municipality/barangay cascade and the map pin are each a
    // property of the address as a whole, not any single field.
    if (!_hasBarangaySelected) {
      setState(() {
        _errorMessage = 'Please select your Region, Province, '
            'City/Municipality, and Barangay before continuing.';
      });
      return;
    }
    if (!_hasAddressPin) {
      setState(() {
        _errorMessage = 'Please tap "Pick on Map" and pin your exact '
            'location before continuing.';
      });
      return;
    }

    final bool confirmed = await confirmPhAddress(
      context: context,
      houseNo: _houseNoController.text.trim(),
      street: _streetController.text.trim(),
      purok: _purokController.text.trim(),
      barangay: _barangayName!,
      municipality: _municipalityName!,
      province: _provinceName!,
      landmark: _landmarkController.text.trim(),
      hasPin: _hasAddressPin,
    );
    if (!confirmed) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    // Tracks whether the Firebase Auth account itself was created, so the
    // catch-all below can tell "failed before creating anything" apart
    // from "account exists but saving the profile afterwards failed" -
    // those need very different messages.
    bool accountCreated = false;

    try {
      // Reconstruct the legacy "09XXXXXXXXX" local-format number from the
      // country-code field so existing storage/login lookup logic (which
      // expects that 11-digit format) keeps working unchanged. For PH
      // (+63), the field gives us the 10-digit national number without
      // the leading 0, so we add it back. Other countries are stored as
      // dial-code + national number with no assumed leading 0.
      final String mobileDigits = _mobileCountryDialCode == '+63'
          ? '0$_mobileNationalNumber'
          : '$_mobileCountryDialCode$_mobileNationalNumber';
      final String enteredEmail = _emailController.text.trim();

      // Email is optional. Firebase Auth's email/password provider still
      // needs *some* unique email internally, so accounts registered
      // without one get a synthetic placeholder built from their mobile
      // number - it's never shown anywhere and is only used so
      // signInWithEmailAndPassword has something to sign in with.
      final String authEmail = enteredEmail.isNotEmpty
          ? enteredEmail
          : '$mobileDigits@phone.almares328.app';

      // A mobile number must map to exactly one account, regardless of
      // whether an email was given - two customers could otherwise end up
      // sharing one number, which would make phone-number login pick the
      // wrong account. Firestore's `users` collection isn't publicly
      // readable anymore (only a signed-in customer can read their own
      // doc), and there's no signed-in customer yet at sign-up - so this
      // goes through the login-guard Supabase function instead of a direct
      // Firestore query.
      try {
        final taken = await LoginGuardApi.instance.checkTaken(
          mobile: mobileDigits,
        );
        if (taken.mobileTaken) {
          throw FirebaseAuthException(
            code: 'mobile-already-in-use',
            message: 'An account already exists for that mobile number.',
          );
        }
      } on FirebaseAuthException {
        rethrow;
      } catch (_) {
        // This lookup is a nice-to-have early check, not a hard
        // requirement - if it can't run (e.g. no network yet, or it's been
        // rate-limited), don't block registration on it. Firebase Auth
        // will still catch a genuine duplicate email if one was given.
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: authEmail,
            password: _passwordController.text,
          );
      accountCreated = true;

      final String firstName = _firstNameController.text.trim();
      final String middleInitial = _middleInitialController.text.trim();
      final String lastName = _lastNameController.text.trim();
      final String fullName = middleInitial.isEmpty
          ? '$firstName $lastName'
          : '$firstName ${middleInitial.replaceAll('.', '')}. $lastName';

      await credential.user?.updateDisplayName(fullName);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
            'firstName': firstName,
            'middleInitial': middleInitial,
            'lastName': lastName,
            'fullName': fullName,
            'mobileNumber': mobileDigits,
            'address': _combinedAddressText,
            'houseNo': _houseNoController.text.trim(),
            'street': _streetController.text.trim(),
            'purok': _purokController.text.trim(),
            'region': _regionName,
            'regionCode': _regionCode,
            'province': _provinceName,
            'provinceCode': _provinceCode,
            'municipality': _municipalityName,
            'municipalityCode': _municipalityCode,
            'barangay': _barangayName,
            'barangayCode': _barangayCode,
            if (_hasAddressPin) 'addressLat': _addressLat,
            if (_hasAddressPin) 'addressLng': _addressLng,
            'landmark': _landmarkController.text.trim(),
            // What the customer actually gave us - blank if they skipped
            // it. Use authEmail (below) for anything sign-in related.
            'email': enteredEmail,
            // Always set - this is what Firebase Auth actually has on
            // file for this account, real or synthetic. Login looks this
            // up for mobile-number sign-in.
            'authEmail': authEmail,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account created successfully!'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );

      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.pop(context);
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // A single, persistent on-screen banner (below the fields) is the
      // only warning shown - no snackbar as well, so there's just one
      // place to look.
      setState(() => _errorMessage = _mapAuthError(e));
    } catch (e) {
      if (!mounted) return;
      // accountCreated tells apart two very different failures: one where
      // nothing was created yet (show the real cause), and one where the
      // Auth account exists but the Firestore profile write failed.
      setState(() {
        _errorMessage = accountCreated
            ? 'Account created, but saving your profile details failed: $e. '
                  'Please try updating your profile later.'
            : 'Could not create account: $e';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _registerWithGoogle() async {
    setState(() {
      _isGoogleSubmitting = true;
      _errorMessage = null;
    });

    try {
      final googleSignIn = GoogleSignIn();
      // Same reasoning as the Login screen's Google button: without this,
      // the plugin silently reuses whatever Google account is already
      // cached on the device instead of showing the account picker, so
      // there'd be no way to pick a different (possibly already-registered)
      // Gmail to sign up with.
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // Customer closed the account picker - not an error, just bail out.
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final oauthCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        oauthCredential,
      );
      final user = userCredential.user;
      if (user == null) return;

      // Sign up must only work for a Google account that isn't already
      // registered in this app - if it already has a Firestore profile,
      // send them to Login instead of silently reusing it here.
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final existingDoc = await docRef.get();
      ReadCounter.log(
        'register_screen:googleCheck',
        existingDoc.exists ? 1 : 0,
      );
      if (existingDoc.exists) {
        await FirebaseAuth.instance.signOut();
        await googleSignIn.signOut();
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'An account already exists for this Google account. '
              'Please log in instead.';
        });
        return;
      }

      // Mobile number and address aren't available from Google, so they're
      // left blank, same as every other optional field here - the
      // customer can fill those in later from Edit Profile.
      final String fullName = (user.displayName ?? '').trim();
      final List<String> nameParts = fullName.isEmpty
          ? []
          : fullName.split(RegExp(r'\s+'));
      final String firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final String lastName = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : '';

      await docRef.set({
        'firstName': firstName,
        'middleInitial': '',
        'lastName': lastName,
        'fullName': fullName.isNotEmpty ? fullName : (user.email ?? ''),
        'mobileNumber': '',
        'address': '',
        'email': user.email ?? '',
        'authEmail': user.email ?? '',
        'signInMethod': 'google',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account created successfully!'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );

      // Unlike the email/password flow above (which pops back to a Login
      // screen the customer still has to use), signing in with Google
      // already fully authenticated them - there's no separate credential
      // left to log in with, so go straight into the app instead.
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(const HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _mapAuthError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Google sign-up failed: $e');
    } finally {
      if (mounted) setState(() => _isGoogleSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 20,
                  bottom: 32,
                  left: 24,
                  right: 24,
                ),
                decoration: const BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: const [
                    Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Join Almares 328 today',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FIRST NAME',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'First name is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'e.g. Zeus Mario',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          const Text(
                            'MIDDLE INITIAL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(OPTIONAL)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _middleInitialController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 1,
                        validator: (value) {
                          if (value != null &&
                              value.trim().isNotEmpty &&
                              !RegExp(r'^[a-zA-Z]$').hasMatch(value.trim())) {
                            return 'Enter a single letter';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'e.g. D',
                          icon: Icons.person_outline,
                        ).copyWith(counterText: ''),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'LAST NAME',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Last name is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'e.g. Zepp',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),

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
                        decoration: InputDecoration(
                          hintText: '9XX XXX XXXX',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (phone) {
                          _mobileCountryDialCode = phone.countryCode;
                          _mobileNationalNumber = phone.number;
                        },
                        validator: (phone) {
                          if (phone == null || phone.number.trim().isEmpty) {
                            return 'Mobile number is required';
                          }
                          // For PH, the national number should be exactly
                          // 10 digits (matches the legacy 09XXXXXXXXX
                          // format once the leading 0 is added back).
                          if (phone.countryCode == '+63' &&
                              phone.number.trim().length != 10) {
                            return 'Enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Please double-check your number - our logistics '
                        'team will contact you on this number for delivery.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'ADDRESS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(REQUIRED)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _pickAddressOnMap,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A pin (tap "Pick on Map" above) is also required - '
                        'it\'s what keeps your delivery fee accurate.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _addressSubLabel('Region'),
                      PhLocationSelectField(
                        hint: _phLocationsError != null
                            ? "Couldn't load - tap to retry"
                            : (_phLocations == null
                                  ? 'Loading regions...'
                                  : 'Select Region'),
                        icon: _phLocationsError != null
                            ? Icons.refresh
                            : Icons.map_outlined,
                        value: _regionName,
                        enabled: _phLocations != null || _phLocationsError != null,
                        onTap: _phLocationsError != null
                            ? _loadPhLocationsData
                            : _pickRegion,
                      ),
                      if (_phLocationsError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _phLocationsError!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.redAccent.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _addressSubLabel('Province'),
                      PhLocationSelectField(
                        hint: 'Select Province',
                        icon: Icons.terrain_outlined,
                        value: _provinceName,
                        enabled: _regionCode != null,
                        onTap: _pickProvince,
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('City/Municipality'),
                      PhLocationSelectField(
                        hint: 'Select City/Municipality',
                        icon: Icons.location_city_outlined,
                        value: _municipalityName,
                        enabled: _provinceCode != null,
                        onTap: _pickMunicipality,
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('Barangay'),
                      PhLocationSelectField(
                        hint: _isLoadingBarangays
                            ? 'Loading barangays...'
                            : 'Select Barangay',
                        icon: Icons.holiday_village_outlined,
                        value: _barangayName,
                        enabled: _municipalityCode != null &&
                            !_isLoadingBarangays,
                        onTap: _pickBarangay,
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('House/Lot No.'),
                      TextFormField(
                        controller: _houseNoController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'House/Lot No. is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'e.g. 123',
                          icon: Icons.tag_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('Street'),
                      TextFormField(
                        controller: _streetController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Street is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'e.g. Mabini Street',
                          icon: Icons.signpost_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('Purok', optional: true),
                      TextFormField(
                        controller: _purokController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _fieldDecoration(
                          hint: 'e.g. 5 (leave blank if none)',
                          icon: Icons.signpost_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          const Text(
                            'LANDMARK',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(OPTIONAL)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _landmarkController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _fieldDecoration(
                          hint: 'e.g. Near Jollibee, beside the chapel',
                          icon: Icons.push_pin_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          const Text(
                            'EMAIL ADDRESS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(OPTIONAL)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            // Optional - you can register with just a
                            // mobile number and no email at all.
                            return null;
                          }
                          final emailRegex = RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          );
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Enter a valid email address';
                          }
                          if (looksAllCaps(value.trim())) {
                            return 'Email cannot be in all caps. Check Caps Lock.';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'you@email.com',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'PASSWORD',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        // Some IMEs render a character's "composing" preview
                        // even while obscureText is true, and that preview
                        // can get stuck showing after toggling the eye icon.
                        // Turning off autocorrect/suggestions stops the
                        // keyboard from composing at all, which is the
                        // standard fix for that.
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'Min. 8 characters',
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'CONFIRM PASSWORD',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please re-enter your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'Re-enter password',
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.redAccent.shade700,
                                    fontWeight: FontWeight.w600,
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
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isSubmitting || _isGoogleSubmitting)
                              ? null
                              : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                            elevation: 3,
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
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: (_isSubmitting || _isGoogleSubmitting)
                              ? null
                              : _registerWithGoogle,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          icon: _isGoogleSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: primaryGreen,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/google_logo.png',
                                  width: 20,
                                  height: 20,
                                ),
                          label: const Text(
                            'Sign up with Google',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                              children: const [
                                TextSpan(text: 'Already have an account? '),
                                TextSpan(
                                  text: 'Login',
                                  style: TextStyle(
                                    color: primaryGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
