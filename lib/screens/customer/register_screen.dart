import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/routing.dart';
import '../../core/validators.dart';
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
  final TextEditingController _addressController = TextEditingController();
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
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
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
      // wrong account.
      try {
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .where('mobileNumber', isEqualTo: mobileDigits)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          throw FirebaseAuthException(
            code: 'mobile-already-in-use',
            message: 'An account already exists for that mobile number.',
          );
        }
      } on FirebaseAuthException {
        rethrow;
      } catch (_) {
        // This lookup is a nice-to-have early check, not a hard
        // requirement - if it can't run (e.g. no network yet), don't
        // block registration on it. Firebase Auth will still catch a
        // genuine duplicate email if one was given.
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
            'address': _addressController.text.trim(),
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
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
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
      if (existingDoc.exists) {
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
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
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _addressController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Address is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'House No., Street, Barangay',
                          icon: Icons.location_on_outlined,
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
