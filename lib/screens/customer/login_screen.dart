import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/onesignal_service.dart';
import '../../services/suspension_service.dart';
import '../../widgets/suspended_account_overlay.dart';
import '../../core/routing.dart';
import '../../core/validators.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? snackBarMessage;
  // Set by the background suspension watcher when it forces a signed-in
  // customer back to this screen mid-session - when present, the glass
  // "account suspended" overlay is shown automatically as soon as this
  // screen appears, using the same widget the login-time suspension
  // check below uses.
  final String? suspendedReason;
  final DateTime? suspendedUntil;
  const LoginScreen({
    super.key,
    this.snackBarMessage,
    this.suspendedReason,
    this.suspendedUntil,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.suspendedUntil != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSuspendedAccountOverlay(
          context,
          reason: widget.suspendedReason,
          suspendedUntil: widget.suspendedUntil,
        );
      });
    }
    if (widget.snackBarMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.snackBarMessage!),
            backgroundColor: primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      });
    }
  }

  bool _isSubmitting = false;
  // Shown as a persistent banner (not just a snackbar that can be missed
  // or dismissed) so the exact reason login failed is always visible on
  // screen until the next attempt. Suspension no longer goes through
  // this banner - it gets the dedicated glass overlay instead.
  String? _errorMessage;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static const Color primaryGreen = Color(0xFF2E6B3E);

  // Checked by default - matches most apps' default of staying signed in.
  // When unchecked, the splash screen signs the customer back out on the
  // app's next cold start instead of dropping them straight into HomeScreen.
  bool _keepLoggedIn = true;
  static const String _keepLoggedInPrefsKey = 'keepLoggedIn';
  // Remembers which provider the customer most recently signed in with.
  // splash_screen.dart reads this to decide whether it's worth attempting
  // a Google-session fallback when Firebase Auth's own persisted session
  // comes back empty on a cold start - that fallback only makes sense for
  // an account that actually signed in with Google.
  static const String _lastSignInWasGooglePrefsKey = 'lastSignInWasGoogle';

  // Firebase Auth's own persisted session doesn't reliably survive this
  // app being killed from the recent-apps list on every device - Google
  // logins get around that via Google Sign-In's separate, outside-the-app
  // session (see splash_screen.dart). Email/password has no equivalent
  // outside layer to lean on, so the only way to silently restore it on
  // the next cold start is to keep the credentials themselves ready to
  // replay - kept in the device's hardware-backed secure storage (Android
  // Keystore / iOS Keychain), never in plain SharedPreferences, and only
  // ever written when "keep me logged in" is actually checked. Cleared
  // immediately on manual logout, a forced sign-out, or switching to
  // Google login - see profile_tab.dart and suspension_watcher.dart.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _savedEmailKey = 'savedLoginEmail';
  static const String _savedPasswordKey = 'savedLoginPassword';

  Future<void> _savePersistencePreference({
    required bool isGoogle,
    String? email,
    String? password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keepLoggedInPrefsKey, _keepLoggedIn);
      await prefs.setBool(_lastSignInWasGooglePrefsKey, isGoogle);
    } catch (_) {
      // Non-critical - worst case the app just defaults to staying signed
      // in on the next cold start.
    }

    try {
      if (!isGoogle && _keepLoggedIn && email != null && password != null) {
        await _secureStorage.write(key: _savedEmailKey, value: email);
        await _secureStorage.write(key: _savedPasswordKey, value: password);
      } else {
        // Google login, or "keep me logged in" unchecked - nothing for
        // the email/password fallback to use, so make sure nothing stale
        // is left behind from an earlier login.
        await _secureStorage.delete(key: _savedEmailKey);
        await _secureStorage.delete(key: _savedPasswordKey);
      }
    } catch (_) {
      // Non-critical - worst case the email/password fallback just can't
      // run on the next cold start.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'no-email-on-file':
        return 'This account has no email on file. Please log in with your email address instead.';
      default:
        // Fall back to whatever Firebase actually says rather than a
        // generic message - that's the difference between "try again"
        // and knowing exactly what to fix.
        return (e.message != null && e.message!.isNotEmpty)
            ? 'Login failed: ${e.message}'
            : 'Login failed (${e.code}). Please try again.';
    }
  }

  // Checked right after Firebase Auth confirms sign-in, before the
  // customer is let into the app - staff suspend accounts from the web
  // admin panel by writing a `suspendedUntil` Timestamp onto
  // users/{uid}; no field (or a date that's already passed) means the
  // account isn't suspended. Shares its logic with the background
  // suspension_watcher.dart, which runs the same check continuously
  // while the app is open. Returns true if the account is suspended -
  // in that case it has already been signed back out and the glass
  // overlay shown, so the caller should just stop and not navigate
  // anywhere.
  Future<bool> _checkAndHandleSuspension(String uid) async {
    try {
      final result = await checkAccountSuspension(uid);
      if (result.isSuspended) {
        // Detach this device from the account before signing back out -
        // covers the case where this device was already linked to this
        // uid from a previous, non-suspended session.
        unawaited(
          OneSignalService.instance.logout().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          ),
        );
        await FirebaseAuth.instance.signOut();
        if (!mounted) return true;
        await showSuspendedAccountOverlay(
          context,
          reason: result.reason,
          suspendedUntil: result.suspendedUntil,
        );
        return true;
      }
      return false;
    } catch (_) {
      // If the suspension check itself can't run (e.g. no connection),
      // don't lock a legitimate customer out over it - treat it the same
      // as "not suspended" rather than blocking login on a lookup error.
      return false;
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final String input = _emailController.text.trim();

    try {
      String email;

      if (input.contains('@')) {
        email = input;
      } else {
        final digitsOnly = input.replaceAll(RegExp(r'[^0-9]'), '');
        // No .limit(1) - if more than one account record shares this
        // mobile number (e.g. a leftover/duplicate from earlier testing),
        // pick the one that actually resolves to a sign-in email instead
        // of blindly taking whichever one Firestore returns first.
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('mobileNumber', isEqualTo: digitsOnly)
            .get();

        if (query.docs.isEmpty) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'No account found for that mobile number.',
          );
        }

        String? foundEmail;
        for (final doc in query.docs) {
          final data = doc.data();
          // authEmail is what Firebase Auth actually has on file for this
          // account - set for every account registered with the phone-only
          // flow (it's a real email if they gave one, otherwise a
          // synthetic placeholder). Older accounts predating that field
          // fall back to the plain email column.
          final String? candidate =
              (data['authEmail'] as String?) ?? (data['email'] as String?);
          if (candidate != null && candidate.isNotEmpty) {
            foundEmail = candidate;
            break;
          }
        }
        if (foundEmail == null) {
          // Every matching account record has no usable email on file -
          // sign in with email instead of crashing on a null cast.
          throw FirebaseAuthException(
            code: 'no-email-on-file',
            message: 'This account has no email on file.',
          );
        }
        email = foundEmail;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Suspended accounts must never reach the app - check immediately
      // after authenticating, before anything else (push notification
      // linking, persistence, navigation) has a chance to run.
      if (uid != null && await _checkAndHandleSuspension(uid)) {
        return;
      }

      if (uid != null) {
        // Link push notifications in the background instead of awaiting it
        // here - if OneSignal is slow or unreachable, that must never stop
        // an already-authenticated customer from getting into the app.
        unawaited(
          OneSignalService.instance
              .login(uid)
              .timeout(const Duration(seconds: 5), onTimeout: () {}),
        );
      }
      await _savePersistencePreference(
        isGoogle: false,
        email: email,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(const HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // A single, persistent on-screen banner (below the fields) is the
      // only warning shown - no snackbar as well, so there's just one
      // place to look.
      setState(() => _errorMessage = _mapAuthError(e));
    } catch (e) {
      // Catch-all so an unexpected error always surfaces some feedback
      // instead of leaving the customer staring at a spinner that quietly
      // resets with nothing else happening.
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _isGoogleSubmitting = false;

  Future<void> _loginWithGoogle() async {
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

      // Login must only work for an account that already exists - this
      // button is not allowed to silently create one (that's what Sign Up
      // With Google on the Register screen is for). A Google identity
      // counts as "registered" once it has a Firestore profile.
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        // Firebase Auth itself auto-creates the underlying auth record on
        // first Google sign-in (that part can't be prevented client-side),
        // but with no Firestore profile this still isn't a real account in
        // this app - sign back out and send them to register instead.
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'No account found for this Google account. Please register first.';
        });
        return;
      }

      // Same suspension check as email/password login - a customer can't
      // get around a suspension just by signing in with Google instead.
      if (await _checkAndHandleSuspension(user.uid)) {
        return;
      }

      // Same reasoning as at email/password login: never let a slow or
      // unreachable OneSignal call block getting into the app.
      unawaited(
        OneSignalService.instance
            .login(user.uid)
            .timeout(const Duration(seconds: 5), onTimeout: () {}),
      );

      await _savePersistencePreference(isGoogle: true);
      if (!mounted) return;
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
      setState(() => _errorMessage = 'Google sign-in failed: $e');
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
                  bottom: 40,
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
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: primaryGreen,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Welcome Back!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in to your Almares 328 account',
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
                        'EMAIL OR MOBILE NUMBER',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email or mobile number is required';
                          }
                          final trimmed = value.trim();

                          if (trimmed.contains('@')) {
                            final emailRegex = RegExp(
                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                            );
                            if (!emailRegex.hasMatch(trimmed)) {
                              return 'Enter a valid email address';
                            }
                            if (looksAllCaps(trimmed)) {
                              return 'Email cannot be in all caps. Check Caps Lock.';
                            }
                          } else {
                            final digitsOnly = trimmed.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            if (!RegExp(r'^09\d{9}$').hasMatch(digitsOnly)) {
                              return 'Enter a valid email or mobile number';
                            }
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter your email or mobile number',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            color: Colors.grey,
                          ),
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
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: Colors.grey,
                          ),
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
                      ),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(
                                () => _keepLoggedIn = !_keepLoggedIn,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: _keepLoggedIn,
                                      activeColor: primaryGreen,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (value) {
                                        setState(
                                          () => _keepLoggedIn =
                                              value ?? true,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Keep me logged in',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
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
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isSubmitting || _isGoogleSubmitting)
                              ? null
                              : _login,
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
                                  'Login',
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
                          onPressed:
                              (_isSubmitting || _isGoogleSubmitting)
                              ? null
                              : _loginWithGoogle,
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
                            'Log in with Google',
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterScreen(),
                              ),
                            );
                          },
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                              children: const [
                                TextSpan(text: "Don't have an account? "),
                                TextSpan(
                                  text: 'Register here',
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
