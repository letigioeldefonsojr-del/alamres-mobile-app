import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'firebase_options.dart';
import 'services/onesignal_service.dart';
import 'services/onesignal_push_sender.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF2E6B3E),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kIsWeb) {
    await OneSignalService.instance.init(
      'c3b735fb-99e4-49be-8f63-e8606b95d918',
    );
    await OneSignal.Notifications.requestPermission(true);
  }

  if (FirebaseAuth.instance.currentUser != null) {
    await OneSignalService.instance.login(
      FirebaseAuth.instance.currentUser!.uid,
    );
  }

  runApp(const MyApp());
}

Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final fade = Tween<double>(begin: 0, end: 1).animate(curved);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

bool _looksAllCaps(String value) {
  final letters = value.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.isNotEmpty && letters == letters.toUpperCase();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Almares 328 Login',
      theme: ThemeData(
        primaryColor: const Color(0xFF2E6B3E),
        fontFamily: 'BricolageGrotesque',
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        Navigator.pushReplacement(
          context,
          fadeSlideRoute(const RoleSelectionScreen()),
        );
        return;
      }

      final employeeDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (employeeDoc.exists) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;

        if (refreshedUser != null && !refreshedUser.emailVerified) {
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(EmployeeVerifyEmailScreen(user: refreshedUser)),
          );
          return;
        }

        final bool activated =
            (employeeDoc.data()?['activated'] as bool?) ?? false;
        if (!activated) {
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(const EmployeeActivationScreen()),
          );
          return;
        }

        Navigator.pushReplacement(
          context,
          fadeSlideRoute(const EmployeeHomeScreen()),
        );
      } else {
        Navigator.pushReplacement(context, fadeSlideRoute(const HomeScreen()));
      }
    });
  }

  Widget _dot(bool active) {
    return Container(
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? 1 : 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 88,
                height: 88,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Almares 328',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'MOBILE ORDERING SYSTEM',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dot(false),
                  const SizedBox(width: 6),
                  _dot(true),
                  const SizedBox(width: 6),
                  _dot(false),
                ],
              ),
              const Spacer(flex: 4),
              Text(
                'Almares 328 — Your trusted sari-sari store, online.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Welcome to Almares 328',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Please select how you'd like to continue",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 36),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      fadeSlideRoute(const LoginScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 3,
                  ),
                  icon: const Icon(Icons.person_outline, color: Colors.white),
                  label: const Text(
                    "I'm a Customer",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      fadeSlideRoute(const EmployeeLoginScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryGreen, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  icon: const Icon(Icons.badge_outlined, color: primaryGreen),
                  label: const Text(
                    "I'm an Employee",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primaryGreen,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No employee account found.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect username/email or password.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final String input = _usernameController.text.trim();

    try {
      String email;

      if (input.contains('@')) {
        email = input;
      } else {
        final query = await FirebaseFirestore.instance
            .collection('employees')
            .where('username', isEqualTo: input)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'No employee account found.',
          );
        }
        email = query.docs.first.data()['email'] as String;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );

      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final employeeDoc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(user.uid)
            .get();

        if (!employeeDoc.exists) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'No employee account found.',
          );
        }
      }

      await user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null && !refreshedUser.emailVerified) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          fadeSlideRoute(EmployeeVerifyEmailScreen(user: refreshedUser)),
          (route) => false,
        );
        return;
      }

      bool activated = false;
      if (refreshedUser != null) {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(refreshedUser.uid)
            .get();
        activated = (doc.data()?['activated'] as bool?) ?? false;
      }

      if (!activated) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          fadeSlideRoute(const EmployeeActivationScreen()),
          (route) => false,
        );
        return;
      }

      final uid = refreshedUser?.uid;
      if (uid != null) await OneSignalService.instance.login(uid);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(const EmployeeHomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mapAuthError(e)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                  top: MediaQuery.of(context).padding.top + 12,
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
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
                        Icons.badge_outlined,
                        color: primaryGreen,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Employee Login',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in to your staff account',
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
                        'USERNAME OR EMAIL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usernameController,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username or email is required';
                          }
                          final trimmed = value.trim();
                          if (trimmed.contains('@') && _looksAllCaps(trimmed)) {
                            return 'Email cannot be in all caps. Check Caps Lock.';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter your username or email',
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
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Password is required'
                            : null,
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
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
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
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _login,
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
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const EmployeeRegisterScreen(),
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
                                TextSpan(text: "Don't have a staff account? "),
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

class EmployeeVerifyEmailScreen extends StatefulWidget {
  final User user;
  const EmployeeVerifyEmailScreen({super.key, required this.user});

  @override
  State<EmployeeVerifyEmailScreen> createState() =>
      _EmployeeVerifyEmailScreenState();
}

class _EmployeeVerifyEmailScreenState extends State<EmployeeVerifyEmailScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isChecking = false;
  bool _isResending = false;

  Future<void> _checkVerified() async {
    setState(() => _isChecking = true);
    try {
      await widget.user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(refreshed.uid)
            .get();
        final bool activated = (doc.data()?['activated'] as bool?) ?? false;

        if (!mounted) return;
        if (activated) {
          Navigator.pushAndRemoveUntil(
            context,
            fadeSlideRoute(const EmployeeHomeScreen()),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            fadeSlideRoute(const EmployeeActivationScreen()),
            (route) => false,
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not verified yet. Please check your inbox.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await widget.user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email resent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not resend email: $e')));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: primaryGreen,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Verify Your Email',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a verification link to ${widget.user.email}. '
                'Please check your inbox and tap the link, then come back here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkVerified,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          "I've Verified My Email",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isResending ? null : _resendEmail,
                child: Text(
                  _isResending ? 'Resending...' : 'Resend Verification Email',
                  style: const TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class EmployeeActivationScreen extends StatefulWidget {
  const EmployeeActivationScreen({super.key});

  @override
  State<EmployeeActivationScreen> createState() =>
      _EmployeeActivationScreenState();
}

class _EmployeeActivationScreenState extends State<EmployeeActivationScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _isSendingOtp = false;
  bool _otpSent = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;

    setState(() {
      _isSendingOtp = true;
      _lastError = null;
    });

    final result = await generateAndSendActivationOtp(user!.uid, user.email!);
    final bool success = result['success'] as bool;
    final String? error = result['error'] as String?;

    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      _otpSent = success;
      _lastError = error;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'A one-time code has been sent to ${user.email}.'
              : 'Could not send code: ${error ?? 'Unknown error'}',
        ),
        backgroundColor: success ? primaryGreen : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _activate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final String enteredCode = _codeController.text.trim();
    if (enteredCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the code sent to your email.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(uid)
          .get();

      final data = doc.data();
      final String? storedOtp = data?['otpCode'] as String?;
      final Timestamp? expiresAt = data?['otpExpiresAt'] as Timestamp?;

      if (storedOtp == null || expiresAt == null) {
        _showError('No active code found. Please resend the code.');
        return;
      }

      if (DateTime.now().isAfter(expiresAt.toDate())) {
        _showError('This code has expired. Please resend a new one.');
        return;
      }

      if (enteredCode != storedOtp) {
        _showError('Incorrect code. Please try again.');
        return;
      }

      await FirebaseFirestore.instance.collection('employees').doc(uid).set({
        'activated': true,
        'otpCode': FieldValue.delete(),
        'otpExpiresAt': FieldValue.delete(),
      }, SetOptions(merge: true));

      await OneSignalService.instance.login(uid);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(const EmployeeHomeScreen()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? email = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: primaryGreen,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Activate Your Account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isSendingOtp
                    ? 'Sending your one-time code...'
                    : (_otpSent
                          ? 'Enter the 6-digit code we sent to $email.'
                          : 'Could not send code. Please try resending.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              if (_lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _lastError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ],
              const SizedBox(height: 32),
              TextFormField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, letterSpacing: 6),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _activate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
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
                          'Activate Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isSendingOtp ? null : _sendOtp,
                child: Text(
                  _isSendingOtp ? 'Sending...' : 'Resend Code',
                  style: const TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class EmployeeRegisterScreen extends StatefulWidget {
  const EmployeeRegisterScreen({super.key});

  @override
  State<EmployeeRegisterScreen> createState() => _EmployeeRegisterScreenState();
}

class _EmployeeRegisterScreenState extends State<EmployeeRegisterScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleInitialController =
      TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureAccessCode = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _accessCodeController.dispose();
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

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      default:
        return 'Could not create account. Please try again.';
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_accessCodeController.text.trim() != kEmployeeAccessCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Incorrect staff access code. Please contact your manager.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final String username = _usernameController.text.trim();

      final existing = await FirebaseFirestore.instance
          .collection('employees')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('That username is already taken.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      final String firstName = _firstNameController.text.trim();
      await credential.user?.updateDisplayName(firstName);
      await credential.user?.sendEmailVerification();

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(credential.user!.uid)
          .set({
            'username': username,
            'firstName': firstName,
            'email': _emailController.text.trim(),
            'contactNumber': _contactController.text.trim(),
            'role': 'employee',
            'activated': false,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Account created! Please check your email to verify your address.',
          ),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );

      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.pop(context);
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mapAuthError(e)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Account created, but saving your profile details failed.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                      'Create Staff Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Join the Almares 328 team',
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
                        'USERNAME',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usernameController,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          if (value.trim().length < 3) {
                            return 'Username must be at least 3 characters';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'e.g. zeusmario.zepp',
                          icon: Icons.alternate_email,
                        ),
                      ),
                      const SizedBox(height: 20),
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
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'First name is required'
                            : null,
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
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Last name is required'
                            : null,
                        decoration: _fieldDecoration(
                          hint: 'e.g. Zepp',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'EMAIL ADDRESS',
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
                            return 'Email is required';
                          }
                          final emailRegex = RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          );
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Enter a valid email address';
                          }
                          if (_looksAllCaps(value.trim())) {
                            return 'Email cannot be in all caps. Check Caps Lock.';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'you@email.com',
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'CONTACT NUMBER',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _contactController,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Contact number is required';
                          }
                          final digitsOnly = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (!RegExp(r'^09\d{9}$').hasMatch(digitsOnly)) {
                            return 'Enter a valid mobile number (09XX XXX XXXX)';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: '09XX XXX XXXX',
                          icon: Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'STAFF ACCESS CODE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ask your manager for this code.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _accessCodeController,
                        obscureText: _obscureAccessCode,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Access code is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: 'Enter staff access code',
                          icon: Icons.vpn_key_outlined,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureAccessCode
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(
                              () => _obscureAccessCode = !_obscureAccessCode,
                            ),
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
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
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
                            onPressed: () => setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
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
                      const SizedBox(height: 20),
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                              children: const [
                                TextSpan(
                                  text: 'Already have a staff account? ',
                                ),
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

class LoginScreen extends StatefulWidget {
  final String? snackBarMessage;
  const LoginScreen({super.key, this.snackBarMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static const Color primaryGreen = Color(0xFF2E6B3E);

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
      default:
        return 'Login failed. Please try again.';
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final String input = _emailController.text.trim();

    try {
      String email;

      if (input.contains('@')) {
        email = input;
      } else {
        final digitsOnly = input.replaceAll(RegExp(r'[^0-9]'), '');
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('mobileNumber', isEqualTo: digitsOnly)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'No account found for that mobile number.',
          );
        }
        email = query.docs.first.data()['email'] as String;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await OneSignalService.instance.login(uid);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(const HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mapAuthError(e)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                            if (_looksAllCaps(trimmed)) {
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

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
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
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _login,
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
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              fadeSlideRoute(const RoleSelectionScreen()),
                              (route) => false,
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            Icons.swap_horiz,
                            size: 16,
                            color: Colors.grey.shade500,
                          ),
                          label: Text(
                            'Not a customer? Switch role',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
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
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
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

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      default:
        return 'Could not create account. Please try again.';
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

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
            'mobileNumber': _mobileController.text.replaceAll(
              RegExp(r'[^0-9]'),
              '',
            ),
            'address': _addressController.text.trim(),
            'email': _emailController.text.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mapAuthError(e)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Account created, but saving your profile details failed. '
            'Please try updating your profile later.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Mobile number is required';
                          }
                          final digitsOnly = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          final mobileRegex = RegExp(r'^09\d{9}$');
                          if (!mobileRegex.hasMatch(digitsOnly)) {
                            return 'Enter a valid mobile number (09XX XXX XXXX)';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          hint: '09XX XXX XXXX',
                          icon: Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'ADDRESS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
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

                      const Text(
                        'EMAIL ADDRESS',
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
                            return 'Email is required';
                          }
                          final emailRegex = RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          );
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Enter a valid email address';
                          }
                          if (_looksAllCaps(value.trim())) {
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
                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
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

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Could not send reset email. Please try again.';
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mapAuthError(e)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: primaryGreen,
              size: 28,
            ),
          ),
          title: const Text(
            'Check Your Email',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'If an account exists for ${_emailController.text.trim()}, '
            'we\'ve sent a link to reset your password.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Back to Login',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
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
                  top: MediaQuery.of(context).padding.top + 12,
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
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        Icons.lock_reset_outlined,
                        color: primaryGreen,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your email and we\'ll send you a reset link',
                      textAlign: TextAlign.center,
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
                        'EMAIL ADDRESS',
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
                            return 'Email is required';
                          }
                          final emailRegex = RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          );
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Enter a valid email address';
                          }
                          if (_looksAllCaps(value.trim())) {
                            return 'Email cannot be in all caps. Check Caps Lock.';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter your email',
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
                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
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
                                  'Send Reset Link',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                              children: [
                                TextSpan(text: 'Remembered it? '),
                                TextSpan(
                                  text: 'Back to Login',
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  int _selectedIndex = 0;

  final List<Widget> _tabs = const [
    HomeTab(),
    CategoriesPlaceholderTab(),
    OrdersPlaceholderTab(),
    ProfileTab(),
  ];

  final List<String> _tabLabels = const [
    'Home',
    'Categories',
    'Orders',
    'Profile',
  ];

  final List<IconData> _tabIcons = const [
    Icons.home_outlined,
    Icons.grid_view_outlined,
    Icons.receipt_long_outlined,
    Icons.person_outline,
  ];

  final List<IconData> _tabIconsFilled = const [
    Icons.home,
    Icons.grid_view,
    Icons.receipt_long,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _selectedIndex, children: _tabs),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabLabels.length, (index) {
                final bool isSelected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? _tabIconsFilled[index] : _tabIcons[index],
                        color: isSelected ? primaryGreen : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabLabels[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected ? primaryGreen : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  int _selectedIndex = 0;

  final List<Widget> _tabs = const [
    EmployeeHomeTab(),
    EmployeeProductsScreen(),
    EmployeeMyOrdersScreen(),
  ];

  final List<String> _tabLabels = const ['Home', 'Products', 'Orders'];

  final List<IconData> _tabIcons = const [
    Icons.home_outlined,
    Icons.inventory_2_outlined,
    Icons.receipt_long_outlined,
  ];

  final List<IconData> _tabIconsFilled = const [
    Icons.home,
    Icons.inventory_2,
    Icons.receipt_long,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _selectedIndex, children: _tabs),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabLabels.length, (index) {
                final bool isSelected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? _tabIconsFilled[index] : _tabIcons[index],
                        color: isSelected ? primaryGreen : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabLabels[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected ? primaryGreen : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class EmployeeNotificationBadge extends StatelessWidget {
  const EmployeeNotificationBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('employeeNotifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final int count = snapshot.data?.docs.length ?? 0;
        if (count <= 0) return const SizedBox.shrink();
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E6B3E), width: 1.5),
          ),
        );
      },
    );
  }
}

class EmployeeNotificationsScreen extends StatefulWidget {
  const EmployeeNotificationsScreen({super.key});

  @override
  State<EmployeeNotificationsScreen> createState() =>
      _EmployeeNotificationsScreenState();
}

class _EmployeeNotificationsScreenState
    extends State<EmployeeNotificationsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance
        .collection('employeeNotifications')
        .doc(docId)
        .update({'read': true});
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, $hour:$minute $period';
  }

  Future<void> _deleteNotification(String docId) async {
    await FirebaseFirestore.instance
        .collection('employeeNotifications')
        .doc(docId)
        .delete();
  }

  Future<void> _markAllRead() async {
    final unread = await FirebaseFirestore.instance
        .collection('employeeNotifications')
        .where('read', isEqualTo: false)
        .get();

    if (unread.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No unread notifications.'),
            backgroundColor: Colors.grey.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('All notifications marked as read.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications'),
        content: const Text(
          'This will permanently delete all notifications. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear All',
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

    final all = await FirebaseFirestore.instance
        .collection('employeeNotifications')
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in all.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Orders Notification'),
        actions: [
          IconButton(
            onPressed: _markAllRead,
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark All as Read',
          ),
          IconButton(
            onPressed: _confirmClearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('employeeNotifications')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_none,
                        color: primaryGreen,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No notifications yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final bool read = (data['read'] as bool?) ?? false;
              final createdAt = data['createdAt'];
              String dateLabel = '';
              if (createdAt is Timestamp) {
                dateLabel = _formatDate(createdAt.toDate());
              }
              return Dismissible(
                key: ValueKey(doc.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => _deleteNotification(doc.id),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: Material(
                  color: read
                      ? const Color(0xFFF5F5F5)
                      : primaryGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: read ? null : () => _markAsRead(doc.id),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF0F0F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: (read ? Colors.grey : primaryGreen)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.receipt_long_outlined,
                              color: read ? Colors.grey.shade500 : primaryGreen,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['message'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: read
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    color: read
                                        ? Colors.grey.shade500
                                        : Colors.black87,
                                  ),
                                ),
                                if (dateLabel.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    dateLabel,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                            onPressed: () => _deleteNotification(doc.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EmployeeProductsScreen extends StatefulWidget {
  const EmployeeProductsScreen({super.key});

  @override
  State<EmployeeProductsScreen> createState() => _EmployeeProductsScreenState();
}

class _EmployeeProductsScreenState extends State<EmployeeProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _sortByStock = false;
  bool _isGridView = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  double _fabOpacity = 0.55;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFabOpacity);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFabOpacity);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateFabOpacity() {
    if (!_scrollController.hasClients) return;
    final bool atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 40;
    final double target = atBottom ? 1.0 : 0.55;
    if (target != _fabOpacity) {
      setState(() => _fabOpacity = target);
    }
  }

  Future<void> _pickSort() async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sort By',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                title: const Text('Default (Newest)'),
                trailing: !_sortByStock
                    ? const Icon(Icons.check, color: primaryGreen)
                    : null,
                onTap: () => Navigator.pop(context, false),
              ),
              ListTile(
                title: const Text('Stock Level (Lowest First)'),
                trailing: _sortByStock
                    ? const Icon(Icons.check, color: primaryGreen)
                    : null,
                onTap: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) setState(() => _sortByStock = selected);
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<String> allIds) {
    setState(() {
      if (_selectedIds.length == allIds.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Products'),
        content: Text(
          'Are you sure you want to remove ${_selectedIds.length} '
          'product${_selectedIds.length == 1 ? '' : 's'}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
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

    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selectedIds) {
      batch.delete(FirebaseFirestore.instance.collection('products').doc(id));
    }
    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_selectedIds.length} product(s) removed.'),
        backgroundColor: primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );

    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _scanToRestock() async {
    final String? productId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const BarcodeScannerScreen(title: 'Scan Product QR'),
      ),
    );
    if (productId == null || !mounted) return;

    final doc = await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .get();

    if (!mounted) return;

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No product found for that QR code.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            QuickRestockScreen(productId: doc.id, data: doc.data()!),
      ),
    );
  }

  void _showProductQr(String productId, String productName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(productName, textAlign: TextAlign.center),
        content: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(data: productId, version: QrVersions.auto),
              ),
              const SizedBox(height: 12),
              Text(
                'Print and stick this QR on the shelf.\nScan it anytime to quickly update stock.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: primaryGreen)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: AnimatedOpacity(
          opacity: _fabOpacity,
          duration: const Duration(milliseconds: 250),
          child: FloatingActionButton.extended(
            backgroundColor: primaryGreen,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddProductScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Add Product',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isSelectionMode
                            ? '${_selectedIds.length} selected'
                            : 'All Products',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isSelectionMode) ...[
                      if (_selectedIds.isNotEmpty)
                        IconButton(
                          onPressed: _bulkDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Delete Selected',
                        ),
                      TextButton(
                        onPressed: _toggleSelectionMode,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ] else ...[
                      IconButton(
                        onPressed: () =>
                            setState(() => _isGridView = !_isGridView),
                        icon: Icon(
                          _isGridView
                              ? Icons.view_list_outlined
                              : Icons.grid_view_outlined,
                          color: primaryGreen,
                        ),
                        tooltip: _isGridView ? 'List View' : 'Grid View',
                      ),
                      IconButton(
                        onPressed: _toggleSelectionMode,
                        icon: const Icon(
                          Icons.checklist_outlined,
                          color: primaryGreen,
                        ),
                        tooltip: 'Select Products',
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: primaryGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'sort':
                              _pickSort();
                              break;
                            case 'import':
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const BulkImportProductsScreen(),
                                ),
                              );
                              break;
                            case 'scan':
                              _scanToRestock();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'sort',
                            child: Row(
                              children: [
                                Icon(Icons.sort, color: primaryGreen, size: 20),
                                SizedBox(width: 12),
                                Text('Sort'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'import',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.upload_file_outlined,
                                  color: primaryGreen,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Text('Bulk Import'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'scan',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.qr_code_scanner,
                                  color: primaryGreen,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Text('Scan to Restock'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('products')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final ids = (snapshot.data?.docs ?? [])
                          .map((d) => d.id)
                          .toList();
                      final bool allSelected =
                          ids.isNotEmpty && _selectedIds.length == ids.length;
                      return GestureDetector(
                        onTap: () => _selectAll(ids),
                        child: Row(
                          children: [
                            Icon(
                              allSelected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: primaryGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              allSelected ? 'Deselect All' : 'Select All',
                              style: const TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Tap the star to feature a product on the Home screen.',
                    style: TextStyle(color: Colors.grey, fontSize: 12.5),
                  ),
                ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('products')
                      .snapshots(),
                  builder: (context, snapshot) {
                    var docs = List.of(snapshot.data?.docs ?? []);

                    if (_searchQuery.trim().isNotEmpty) {
                      final String q = _searchQuery.trim().toLowerCase();
                      docs = docs
                          .where(
                            (doc) => (doc.data()['name'] as String? ?? '')
                                .toLowerCase()
                                .contains(q),
                          )
                          .toList();
                    }

                    if (_sortByStock) {
                      docs.sort(
                        (a, b) => extractTotalStock(
                          a.data(),
                        ).compareTo(extractTotalStock(b.data())),
                      );
                    }

                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: primaryGreen.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _searchQuery.trim().isEmpty
                                      ? Icons.inventory_2_outlined
                                      : Icons.search_off,
                                  color: primaryGreen,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.trim().isEmpty
                                    ? 'No products yet'
                                    : 'No products found for "$_searchQuery"',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (_isGridView) {
                      return GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          100 + MediaQuery.of(context).padding.bottom,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.62,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final bool featured =
                              (data['featured'] as bool?) ?? false;
                          final String name = data['name'] as String? ?? '';
                          final int totalStock = extractTotalStock(data);
                          final bool isOutOfStock = totalStock <= 0;
                          final StockLevel stockLevel = getStockLevel(
                            totalStock,
                          );
                          final bool isSelected = _selectedIds.contains(doc.id);

                          return Material(
                            color: isSelected
                                ? primaryGreen.withValues(alpha: 0.06)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _isSelectionMode
                                  ? () => _toggleSelected(doc.id)
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ProductDetailScreen(
                                                productId: doc.id,
                                                data: data,
                                              ),
                                        ),
                                      );
                                    },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedIds.add(doc.id);
                                  });
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? primaryGreen.withValues(alpha: 0.06)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? primaryGreen
                                        : const Color(0xFFF0F0F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        AspectRatio(
                                          aspectRatio: 1,
                                          child: ProductImage(
                                            imageUrl:
                                                data['imageUrl'] as String?,
                                            iconSize: 30,
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topLeft: Radius.circular(16),
                                                  topRight: Radius.circular(16),
                                                ),
                                          ),
                                        ),
                                        if (_isSelectionMode)
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: Icon(
                                              isSelected
                                                  ? Icons.check_box
                                                  : Icons
                                                        .check_box_outline_blank,
                                              color: primaryGreen,
                                            ),
                                          )
                                        else
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: IconButton(
                                              onPressed: () =>
                                                  setProductFeatured(
                                                    doc.id,
                                                    !featured,
                                                  ),
                                              icon: Icon(
                                                featured
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: featured
                                                    ? Colors.amber
                                                    : Colors.grey.shade400,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Flexible(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          6,
                                          10,
                                          8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                height: 1.15,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    (isOutOfStock
                                                            ? Colors
                                                                  .grey
                                                                  .shade600
                                                            : stockLevelColor(
                                                                stockLevel,
                                                              ))
                                                        .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                isOutOfStock
                                                    ? 'Out of Stock'
                                                    : stockLevelLabel(
                                                        stockLevel,
                                                      ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: isOutOfStock
                                                      ? Colors.grey.shade600
                                                      : stockLevelColor(
                                                          stockLevel,
                                                        ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              productPriceLabel(data),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: primaryGreen,
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
                        },
                      );
                    }

                    return ListView.separated(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        100 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: docs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final bool featured =
                            (data['featured'] as bool?) ?? false;
                        final String name = data['name'] as String? ?? '';
                        final int totalStock = extractTotalStock(data);
                        final bool isOutOfStock = totalStock <= 0;
                        final String stock = productStockLabel(data);
                        final String price = productPriceLabel(data);
                        final StockLevel stockLevel = getStockLevel(totalStock);

                        final bool isSelected = _selectedIds.contains(doc.id);

                        return Material(
                          color: isSelected
                              ? primaryGreen.withValues(alpha: 0.06)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _isSelectionMode
                                ? () => _toggleSelected(doc.id)
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ProductDetailScreen(
                                              productId: doc.id,
                                              data: data,
                                            ),
                                      ),
                                    );
                                  },
                            onLongPress: () {
                              if (!_isSelectionMode) {
                                setState(() {
                                  _isSelectionMode = true;
                                  _selectedIds.add(doc.id);
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryGreen.withValues(alpha: 0.06)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? primaryGreen
                                      : const Color(0xFFF0F0F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (_isSelectionMode) ...[
                                    Icon(
                                      isSelected
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      color: primaryGreen,
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: ProductImage(
                                      imageUrl: data['imageUrl'] as String?,
                                      iconSize: 22,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          stock,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (isOutOfStock
                                                        ? Colors.grey.shade600
                                                        : stockLevelColor(
                                                            stockLevel,
                                                          ))
                                                    .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            isOutOfStock
                                                ? 'Out of Stock'
                                                : stockLevelLabel(stockLevel),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isOutOfStock
                                                  ? Colors.grey.shade600
                                                  : stockLevelColor(stockLevel),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          price,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: primaryGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!_isSelectionMode) ...[
                                    IconButton(
                                      onPressed: () =>
                                          _showProductQr(doc.id, name),
                                      icon: const Icon(
                                        Icons.qr_code_2,
                                        color: primaryGreen,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setProductFeatured(doc.id, !featured),
                                      icon: Icon(
                                        featured
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: featured
                                            ? Colors.amber
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        final confirmed =
                                            await confirmDeleteProduct(
                                              context,
                                              name,
                                            );
                                        if (confirmed) {
                                          await deleteProduct(doc.id);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '$name removed successfully.',
                                                ),
                                                backgroundColor: primaryGreen,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                margin: const EdgeInsets.all(
                                                  16,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantRow {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  String? imageUrl;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
    stockController.dispose();
  }
}

class BulkImportProductsScreen extends StatefulWidget {
  const BulkImportProductsScreen({super.key});

  @override
  State<BulkImportProductsScreen> createState() =>
      _BulkImportProductsScreenState();
}

class _BulkImportProductsScreenState extends State<BulkImportProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  List<Map<String, dynamic>> _parsedProducts = [];
  List<String> _errors = [];
  bool _isParsing = false;
  bool _isImporting = false;
  String? _fileName;

  Future<void> _pickFile() async {
    final params = OpenFileDialogParams(
      dialogType: OpenFileDialogType.document,
      fileExtensionsFilter: ['csv'],
    );

    String? filePath;
    try {
      filePath = await FlutterFileDialog.pickFile(params: params);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'invalid_file_extension') {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Invalid File'),
            content: const Text(
              'That doesn\'t look like a valid CSV file. Please select a file '
              'with a .csv extension (Excel files must be saved as CSV first).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${e.message}')),
        );
      }
      return;
    }

    if (filePath == null) return;

    setState(() {
      _isParsing = true;
      _parsedProducts = [];
      _errors = [];
      _fileName = filePath!.split('/').last;
    });

    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final rows = const CsvToListConverter(eol: '\n').convert(content);

      if (rows.isEmpty) {
        setState(() => _errors = ['File is empty.']);
        return;
      }

      final header = rows.first
          .map((e) => e.toString().trim().toLowerCase())
          .toList();
      final nameIdx = header.indexOf('name');
      final categoryIdx = header.indexOf('category');
      final barcodeIdx = header.indexOf('barcode');
      final priceIdx = header.indexOf('price');
      final stockIdx = header.indexOf('stock');
      final variantNameIdx = header.indexOf('variant_name');
      final variantPriceIdx = header.indexOf('variant_price');
      final variantStockIdx = header.indexOf('variant_stock');

      if (nameIdx == -1 ||
          categoryIdx == -1 ||
          priceIdx == -1 ||
          stockIdx == -1) {
        setState(
          () => _errors = [
            'Missing required columns. Expected: name, category, barcode, price, stock',
          ],
        );
        return;
      }

      String cell(List<dynamic> row, int idx) {
        if (idx == -1 || row.length <= idx) return '';
        return row[idx].toString().trim();
      }

      final validCategories = kProductCategories
          .map((c) => c['label'] as String)
          .toSet();

      final Map<String, Map<String, dynamic>> productsByKey = {};
      final List<String> productOrder = [];
      final List<String> errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) {
          continue;
        }

        final String name = cell(row, nameIdx);
        final String category = cell(row, categoryIdx);
        final String barcode = cell(row, barcodeIdx);
        final String priceRaw = cell(row, priceIdx);
        final String stockRaw = cell(row, stockIdx);
        final String variantName = cell(row, variantNameIdx);
        final String variantPriceRaw = cell(row, variantPriceIdx);
        final String variantStockRaw = cell(row, variantStockIdx);

        if (name.isEmpty) {
          errors.add('Row ${i + 1}: missing product name.');
          continue;
        }
        if (!validCategories.contains(category)) {
          errors.add('Row ${i + 1}: "$category" is not a valid category.');
          continue;
        }

        final String key = '$name|$category';

        if (variantName.isNotEmpty) {
          final double? variantPrice = double.tryParse(variantPriceRaw);
          if (variantPrice == null) {
            errors.add(
              'Row ${i + 1}: invalid variant price "$variantPriceRaw".',
            );
            continue;
          }
          final int? variantStock = int.tryParse(variantStockRaw);
          if (variantStock == null) {
            errors.add(
              'Row ${i + 1}: invalid variant stock "$variantStockRaw".',
            );
            continue;
          }

          productsByKey.putIfAbsent(key, () {
            productOrder.add(key);
            return {
              'name': name,
              'category': category,
              'barcode': barcode.isEmpty ? null : barcode,
              'imageUrl': null,
              'available': true,
              'featured': false,
              'flavors': <Map<String, dynamic>>[],
            };
          });

          (productsByKey[key]!['flavors'] as List<Map<String, dynamic>>).add({
            'name': variantName,
            'price': '₱${variantPrice.toStringAsFixed(2)}',
            'stock': variantStock,
            'available': variantStock > 0,
            'imageUrl': null,
          });
        } else {
          final double? price = double.tryParse(priceRaw);
          if (price == null) {
            errors.add('Row ${i + 1}: invalid price "$priceRaw".');
            continue;
          }
          final int? stock = int.tryParse(stockRaw);
          if (stock == null) {
            errors.add('Row ${i + 1}: invalid stock "$stockRaw".');
            continue;
          }

          productOrder.add(key);
          productsByKey[key] = {
            'name': name,
            'category': category,
            'barcode': barcode.isEmpty ? null : barcode,
            'imageUrl': null,
            'price': '₱${price.toStringAsFixed(2)}',
            'stockCount': stock,
            'available': true,
            'featured': false,
            'flavors': <Map<String, dynamic>>[],
          };
        }
      }

      final List<Map<String, dynamic>> parsed = productOrder
          .map((key) => productsByKey[key]!)
          .toList();

      setState(() {
        _parsedProducts = parsed;
        _errors = errors;
      });
    } catch (e) {
      setState(() => _errors = ['Could not read file: $e']);
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _importProducts() async {
    if (_parsedProducts.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final collection = FirebaseFirestore.instance.collection('products');

      final existingSnapshot = await collection.get();
      final Set<String> existingNames = existingSnapshot.docs
          .map(
            (doc) => (doc.data()['name'] as String? ?? '').trim().toLowerCase(),
          )
          .toSet();

      final List<Map<String, dynamic>> newProducts = [];
      int skippedCount = 0;

      for (final product in _parsedProducts) {
        final String nameKey = (product['name'] as String? ?? '')
            .trim()
            .toLowerCase();
        if (existingNames.contains(nameKey)) {
          skippedCount++;
        } else {
          newProducts.add(product);
          existingNames.add(nameKey);
        }
      }

      if (newProducts.isNotEmpty) {
        const int chunkSize = 450;

        for (int i = 0; i < newProducts.length; i += chunkSize) {
          final chunk = newProducts.sublist(
            i,
            (i + chunkSize > newProducts.length)
                ? newProducts.length
                : i + chunkSize,
          );

          final batch = FirebaseFirestore.instance.batch();
          for (final product in chunk) {
            final docRef = collection.doc();
            batch.set(docRef, {
              ...product,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }
      }

      if (!mounted) return;

      final String message = skippedCount > 0
          ? '${newProducts.length} new product${newProducts.length == 1 ? '' : 's'} added. '
                '$skippedCount already added.'
          : '${newProducts.length} product${newProducts.length == 1 ? '' : 's'} imported successfully!';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Bulk Import Products'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Required: name, category, barcode, price, stock\n'
                  'For variants, add: variant_name, variant_price, variant_stock\n'
                  '(use one row per variant, repeating the same product name)\n'
                  'Photos are added afterward in-app, per product/variant.\n'
                  'Category must exactly match: Canned Goods, Beverages, Snacks, Rice, Frozen Products',
                  style: TextStyle(fontSize: 11.5, color: Colors.black87),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isParsing ? null : _pickFile,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file, color: primaryGreen),
                  label: Text(
                    _fileName ?? 'Choose CSV File',
                    style: const TextStyle(
                      color: primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isParsing) const Center(child: CircularProgressIndicator()),
              if (_errors.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_errors.length} row(s) skipped:',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._errors
                          .take(5)
                          .map(
                            (e) => Text(
                              e,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                      if (_errors.length > 5)
                        Text(
                          '...and ${_errors.length - 5} more.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_parsedProducts.isNotEmpty) ...[
                Text(
                  '${_parsedProducts.length} products ready to import',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: _parsedProducts.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = _parsedProducts[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          p['name'] as String,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        subtitle: Text(
                          (p['flavors'] as List).isNotEmpty
                              ? '${p['category']} • ${(p['flavors'] as List).length} variant(s)'
                              : '${p['category']} • ${p['price']} • ${p['stockCount']} pcs',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isImporting ? null : _importProducts,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: _isImporting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'Import ${_parsedProducts.length} Products',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();

  bool _hasVariants = false;
  bool _isSaving = false;
  String? _selectedCategory;
  String? _imageUrl;
  final List<_VariantRow> _variants = [_VariantRow()];
  final TextEditingController _barcodeController = TextEditingController();

  Future<void> _pickPhoto() async {
    final url = await pickAndUploadProductImage(context);
    if (url != null && mounted) {
      setState(() => _imageUrl = url);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _barcodeController.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const BarcodeScannerScreen(title: 'Scan Product Barcode'),
      ),
    );
    if (result != null && mounted) {
      setState(() => _barcodeController.text = result);
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
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

  void _addVariantRow() {
    setState(() => _variants.add(_VariantRow()));
  }

  void _removeVariantRow(int index) {
    setState(() {
      _variants[index].dispose();
      _variants.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final String name = _nameController.text.trim();

    if (_hasVariants) {
      for (final v in _variants) {
        if (v.nameController.text.trim().isEmpty ||
            v.priceController.text.trim().isEmpty ||
            v.stockController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please fill in all variant fields.')),
          );
          return;
        }
        if (double.tryParse(v.priceController.text.trim()) == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Invalid price for "${v.nameController.text.trim()}".',
              ),
            ),
          );
          return;
        }
        if (int.tryParse(v.stockController.text.trim()) == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Invalid stock for "${v.nameController.text.trim()}".',
              ),
            ),
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    try {
      final Map<String, dynamic> data = {
        'name': name,
        'category': _selectedCategory,
        'barcode': _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        'imageUrl': _imageUrl,
        'available': true,
        'featured': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (_hasVariants) {
        data['flavors'] = _variants.map((v) {
          final int stock = int.parse(v.stockController.text.trim());
          final double price = double.parse(v.priceController.text.trim());
          return {
            'name': v.nameController.text.trim(),
            'price': '₱${price.toStringAsFixed(2)}',
            'stock': stock,
            'available': stock > 0,
            'imageUrl': v.imageUrl,
          };
        }).toList();
      } else {
        final double price = double.parse(_priceController.text.trim());
        final int stock = int.parse(_stockController.text.trim());
        data['price'] = '₱${price.toStringAsFixed(2)}';
        data['stockCount'] = stock;
        data['flavors'] = <Map<String, dynamic>>[];
      }

      await FirebaseFirestore.instance.collection('products').doc().set(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Product added successfully!'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add product: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Add Product'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: ProductImage(
                            imageUrl: _imageUrl,
                            iconSize: 36,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: primaryGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                _label('NAME OF PRODUCT'),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Product name is required'
                      : null,
                  decoration: _fieldDecoration(
                    'e.g. Lucky Me Pancit Canton',
                    Icons.inventory_2_outlined,
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    const Text(
                      'BARCODE / SKU',
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
                  controller: _barcodeController,
                  decoration:
                      _fieldDecoration(
                        'Scan or type manually',
                        Icons.qr_code_scanner,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            color: primaryGreen,
                          ),
                          onPressed: _scanBarcode,
                        ),
                      ),
                ),
                const SizedBox(height: 20),

                _label('CATEGORY'),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  validator: (v) =>
                      v == null ? 'Please select a category' : null,
                  decoration: _fieldDecoration(
                    'Select a category',
                    Icons.category_outlined,
                  ),
                  items: kProductCategories
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['label'] as String,
                          child: Text(c['label'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'This product has flavors / variants',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Switch(
                      activeThumbColor: primaryGreen,
                      value: _hasVariants,
                      onChanged: (v) => setState(() => _hasVariants = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (!_hasVariants) ...[
                  _label('PRICE OF THE PRODUCT'),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Price is required';
                      }
                      if (double.tryParse(v.trim()) == null) {
                        return 'Enter a valid number';
                      }
                      return null;
                    },
                    decoration: _fieldDecoration(
                      'e.g. 17.00',
                      Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _label('TOTAL STOCKS'),
                  TextFormField(
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Stock is required';
                      }
                      if (int.tryParse(v.trim()) == null) {
                        return 'Enter a valid whole number';
                      }
                      return null;
                    },
                    decoration: _fieldDecoration(
                      'e.g. 100',
                      Icons.inventory_outlined,
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'FLAVORS / VARIANTS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addVariantRow,
                        icon: const Icon(
                          Icons.add,
                          size: 18,
                          color: primaryGreen,
                        ),
                        label: const Text(
                          'Add Variant',
                          style: TextStyle(
                            color: primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_variants.length, (index) {
                    final v = _variants[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final url = await pickAndUploadProductImage(
                                    context,
                                  );
                                  if (url != null) {
                                    setState(() => v.imageUrl = url);
                                  }
                                },
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFFE0E0E0),
                                        ),
                                      ),
                                      child: ProductImage(
                                        imageUrl: v.imageUrl,
                                        iconSize: 18,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: -2,
                                      right: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: primaryGreen,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_outlined,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Variant ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              if (_variants.length > 1)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _removeVariantRow(index),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: v.nameController,
                            decoration: InputDecoration(
                              hintText: 'Variant name (e.g. Red / Chili Mansi)',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: v.priceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    hintText: 'Price',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: v.stockController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: 'Stock',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],

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
                            'Save Product',
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

class BarcodeScannerScreen extends StatefulWidget {
  final String title;

  const BarcodeScannerScreen({super.key, this.title = 'Scan Code'});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String? value = barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _handled = true;
    Navigator.pop(context, value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: primaryGreen, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              'Align the code within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeHomeTab extends StatefulWidget {
  const EmployeeHomeTab({super.key});

  @override
  State<EmployeeHomeTab> createState() => _EmployeeHomeTabState();
}

class _EmployeeHomeTabState extends State<EmployeeHomeTab> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(uid)
          .get();
      final username = doc.data()?['username'] as String?;
      if (mounted && username != null && username.trim().isNotEmpty) {
        setState(() => _username = username);
      }
    } catch (_) {}
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _getDisplayName() {
    if (_username != null && _username!.trim().isNotEmpty) {
      return _username!;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      return user!.email!.split('@').first;
    }
    return 'Staff';
  }

  Future<void> _unfeature(String productId) async {
    await setProductFeatured(productId, false);
  }

  Future<void> _showBannerDialog({
    String? currentOffer,
    String? currentDescription,
    String? currentImageUrl,
    DateTime? currentScheduleStart,
    DateTime? currentScheduleEnd,
  }) async {
    final offerController = TextEditingController(text: currentOffer ?? '');
    final descriptionController = TextEditingController(
      text: currentDescription ?? '',
    );
    String? imageUrl = currentImageUrl;
    bool isSaving = false;
    bool useSchedule = currentScheduleEnd != null;
    DateTime? scheduleStart = currentScheduleStart;
    DateTime? scheduleEnd = currentScheduleEnd;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(currentOffer == null ? 'Add Banner' : 'Edit Banner'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final url = await pickAndUploadProductImage(context);
                        if (url != null) {
                          setDialogState(() => imageUrl = url);
                        }
                      },
                      child: Stack(
                        children: [
                          Container(
                            height: 110,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE0E0E0),
                              ),
                            ),
                            child: ProductImage(
                              imageUrl: imageUrl,
                              iconSize: 30,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: primaryGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: offerController,
                      decoration: const InputDecoration(
                        labelText: "Store's Offer",
                        hintText: 'e.g. Free Delivery on Orders over ₱500',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'e.g. Valid for Batangas area only',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: primaryGreen,
                      title: const Text(
                        'Schedule this banner',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: const Text(
                        'Auto-remove after end date',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: useSchedule,
                      onChanged: (v) => setDialogState(() => useSchedule = v),
                    ),
                    if (useSchedule) ...[
                      OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: scheduleStart ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null)
                            setDialogState(() => scheduleStart = picked);
                        },
                        child: Text(
                          scheduleStart == null
                              ? 'Select start date'
                              : formatDiscountDate(scheduleStart!),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                scheduleEnd ??
                                (scheduleStart ?? DateTime.now()).add(
                                  const Duration(days: 7),
                                ),
                            firstDate: scheduleStart ?? DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null)
                            setDialogState(() => scheduleEnd = picked);
                        },
                        child: Text(
                          scheduleEnd == null
                              ? 'Select end date'
                              : formatDiscountDate(scheduleEnd!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final offer = offerController.text.trim();
                          final description = descriptionController.text.trim();
                          if (offer.isEmpty || description.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please fill in both fields.'),
                              ),
                            );
                            return;
                          }
                          if (useSchedule &&
                              (scheduleStart == null ||
                                  scheduleEnd == null ||
                                  !scheduleEnd!.isAfter(scheduleStart!))) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select a valid schedule range.',
                                ),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          await saveStoreBanner(
                            offer: offer,
                            description: description,
                            imageUrl: imageUrl,
                            scheduleStart: useSchedule ? scheduleStart : null,
                            scheduleEnd: useSchedule ? scheduleEnd : null,
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: Text(
                    'Save',
                    style: TextStyle(
                      color: primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteBanner() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Banner'),
        content: const Text(
          'This will remove the banner from the customer home screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await deleteStoreBanner();
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
              24,
              MediaQuery.of(context).padding.top + 20,
              24,
              28,
            ),
            decoration: const BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getDisplayName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EmployeeProfileScreen(),
                            ),
                          );
                        },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Center(
                                child: Icon(
                                  Icons.person_outline,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: EmployeeNotificationBadge(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EmployeeProductsScreen(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey),
                          SizedBox(width: 10),
                          Text(
                            'Search products...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Store Banner',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: storeBannerStream(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();

                if (data == null) {
                  return Material(
                    color: primaryGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _showBannerDialog(),
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: primaryGreen.withValues(alpha: 0.3),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add_circle_outline,
                              color: primaryGreen,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add Banner',
                              style: TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final String offer = data['offer'] as String? ?? '';
                final String description = data['description'] as String? ?? '';
                final String? bannerImage = data['imageUrl'] as String?;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      if (bannerImage != null) ...[
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: ProductImage(
                            imageUrl: bannerImage,
                            iconSize: 24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              offer,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showBannerDialog(
                          currentOffer: offer,
                          currentDescription: description,
                          currentImageUrl: data['imageUrl'] as String?,
                          currentScheduleStart:
                              (data['scheduleStart'] as Timestamp?)?.toDate(),
                          currentScheduleEnd:
                              (data['scheduleEnd'] as Timestamp?)?.toDate(),
                        ),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        onPressed: _confirmDeleteBanner,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('featured', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Featured Products',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.56,
                          ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final product = {...doc.data(), 'id': doc.id};
                        return _EmployeeProductCard(
                          product: product,
                          isStarred: true,
                          onStarTap: () => _unfeature(doc.id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmployeeProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool isStarred;
  final VoidCallback onStarTap;

  const _EmployeeProductCard({
    required this.product,
    required this.isStarred,
    required this.onStarTap,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final String name = product['name'] as String? ?? '';
    final String stock = productStockLabel(product);
    final String price = productPriceLabel(product);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProductImage(
                  imageUrl: product['imageUrl'] as String?,
                  iconSize: 32,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onStarTap,
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(
                          isStarred ? Icons.star : Icons.star_border,
                          color: isStarred ? Colors.amber : Colors.grey,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    stock,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
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

class QuickRestockScreen extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> data;

  const QuickRestockScreen({
    super.key,
    required this.productId,
    required this.data,
  });

  @override
  State<QuickRestockScreen> createState() => _QuickRestockScreenState();
}

class _QuickRestockScreenState extends State<QuickRestockScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isSaving = false;
  late List<Map<String, dynamic>> _flavors;
  late TextEditingController _stockController;

  bool get _hasFlavors => _flavors.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _flavors =
        (widget.data['flavors'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map((f) => Map<String, dynamic>.from(f))
            .toList() ??
        [];
    _stockController = TextEditingController(
      text: (widget.data['stockCount'] as num?)?.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (_hasFlavors) {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.productId)
            .update({'flavors': _flavors});
      } else {
        final int newStock = int.tryParse(_stockController.text.trim()) ?? 0;
        await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.productId)
            .update({'stockCount': newStock, 'available': newStock > 0});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Stock updated.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update stock: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.data['name'] as String? ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Quick Restock'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              if (_hasFlavors)
                Expanded(
                  child: ListView.separated(
                    itemCount: _flavors.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final flavor = _flavors[index];
                      final controller = TextEditingController(
                        text: (flavor['stock'] as num?)?.toString() ?? '0',
                      );
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              flavor['name'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF5F5F5),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (value) {
                                final int newStock = int.tryParse(value) ?? 0;
                                _flavors[index] = {
                                  ...flavor,
                                  'stock': newStock,
                                  'available': newStock > 0,
                                };
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else ...[
                const Text(
                  'TOTAL STOCK',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const Spacer(),
              ],
              const SizedBox(height: 20),
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
                          'Save Stock',
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
    );
  }
}

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> data;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    required this.data,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  Future<void> _editPrice(double currentPrice) async {
    final controller = TextEditingController(
      text: currentPrice.toStringAsFixed(2),
    );
    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Price'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: '₱ ',
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null) return;
              Navigator.pop(context, value.toStringAsFixed(2));
            },
            child: const Text(
              'Save',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == null) return;

    await FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .update({'price': '₱$result'});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Price updated.'),
        backgroundColor: primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _editCategory(String? currentCategory) async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Category'),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: kProductCategories.map((c) {
                  final String label = c['label'] as String;
                  final bool isSelected = label == currentCategory;
                  return ListTile(
                    leading: Icon(c['icon'] as IconData, color: primaryGreen),
                    title: Text(label),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: primaryGreen)
                        : null,
                    onTap: () => Navigator.pop(context, label),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    if (result == null || result == currentCategory) return;

    await FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .update({'category': result});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Category updated.'),
        backgroundColor: primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _editVariantName(
    List<Map<String, dynamic>> flavors,
    int index,
  ) async {
    final controller = TextEditingController(
      text: flavors[index]['name'] as String? ?? '',
    );
    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Variant Name'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.pop(context, trimmed);
            },
            child: const Text(
              'Save',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName == null) return;

    final updated = List<Map<String, dynamic>>.from(flavors);
    updated[index] = {...updated[index], 'name': newName};

    await FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .update({'flavors': updated});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Variant name updated.'),
        backgroundColor: primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _addVariant(List<Map<String, dynamic>> flavors) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final stockController = TextEditingController();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Variant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Variant name (e.g. Red)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(hintText: 'Price'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: stockController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Stock'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Add',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final String name = nameController.text.trim();
    final double? price = double.tryParse(priceController.text.trim());
    final int? stock = int.tryParse(stockController.text.trim());

    if (name.isEmpty || price == null || stock == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in a valid name, price, and stock.'),
        ),
      );
      return;
    }

    final updated = List<Map<String, dynamic>>.from(flavors)
      ..add({
        'name': name,
        'price': '₱${price.toStringAsFixed(2)}',
        'stock': stock,
        'available': stock > 0,
        'imageUrl': null,
      });

    await FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .update({'flavors': updated});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name added.'),
        backgroundColor: primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _manageDiscount(Map<String, dynamic> data) async {
    final bool hasDiscount = data['discountPercent'] != null;
    final percentController = TextEditingController(
      text: hasDiscount ? (data['discountPercent'] as num).toString() : '',
    );
    DateTime? start = (data['discountStart'] as Timestamp?)?.toDate();
    DateTime? end = (data['discountEnd'] as Timestamp?)?.toDate();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(hasDiscount ? 'Edit Discount' : 'Set Discount'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: percentController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Discount (%)',
                        hintText: 'e.g. 20',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'FROM',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: start ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null)
                          setDialogState(() => start = picked);
                      },
                      child: Text(
                        start == null
                            ? 'Select start date'
                            : formatDiscountDate(start!),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'UNTIL',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              end ??
                              (start ?? DateTime.now()).add(
                                const Duration(days: 7),
                              ),
                          firstDate: start ?? DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) setDialogState(() => end = picked);
                      },
                      child: Text(
                        end == null
                            ? 'Select end date'
                            : formatDiscountDate(end!),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (hasDiscount)
                  TextButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('products')
                          .doc(widget.productId)
                          .update({
                            'discountPercent': FieldValue.delete(),
                            'discountStart': FieldValue.delete(),
                            'discountEnd': FieldValue.delete(),
                          });
                      if (context.mounted) Navigator.pop(context, false);
                    },
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final percent = double.tryParse(
                      percentController.text.trim(),
                    );
                    if (percent == null || percent <= 0 || percent >= 100) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a valid discount between 1-99%.',
                          ),
                        ),
                      );
                      return;
                    }
                    if (start == null || end == null || !end!.isAfter(start!)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a valid date range.'),
                        ),
                      );
                      return;
                    }
                    await FirebaseFirestore.instance
                        .collection('products')
                        .doc(widget.productId)
                        .update({
                          'discountPercent': percent,
                          'discountStart': Timestamp.fromDate(start!),
                          'discountEnd': Timestamp.fromDate(end!),
                        });
                    if (context.mounted) Navigator.pop(context, true);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Discount saved.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _editName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Product Name'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.pop(context, trimmed);
            },
            child: const Text(
              'Save',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName == null || newName == currentName) return;

    await FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .update({'name': newName});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Product name updated.'),
        backgroundColor: primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? widget.data;

        final String name = data['name'] as String? ?? '';
        final String? category = data['category'] as String?;
        final String? barcode = data['barcode'] as String?;
        final bool featured = (data['featured'] as bool?) ?? false;
        final List<Map<String, dynamic>> flavors =
            (data['flavors'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map((f) => Map<String, dynamic>.from(f))
                .toList() ??
            [];
        final bool hasFlavors = flavors.isNotEmpty;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            title: const Text('Product Details'),
            actions: [
              IconButton(
                icon: Icon(featured ? Icons.star : Icons.star_border),
                onPressed: () =>
                    setProductFeatured(widget.productId, !featured),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final confirmed = await confirmDeleteProduct(context, name);
                  if (confirmed) {
                    await deleteProduct(widget.productId);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$name removed successfully.'),
                          backgroundColor: primaryGreen,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final url = await pickAndUploadProductImage(context);
                      if (url == null) return;
                      await FirebaseFirestore.instance
                          .collection('products')
                          .doc(widget.productId)
                          .update({'imageUrl': url});
                    },
                    child: Stack(
                      children: [
                        SizedBox(
                          height: 140,
                          width: double.infinity,
                          child: ProductImage(
                            imageUrl: data['imageUrl'] as String?,
                            iconSize: 40,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: primaryGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => _editName(name),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  GestureDetector(
                    onTap: () => _editCategory(category),
                    child: _detailRow('Category', category ?? 'Tap to set'),
                  ),
                  if (barcode != null && barcode.isNotEmpty)
                    _detailRow('Barcode / SKU', barcode),
                  _detailRow('Stock Summary', productStockLabel(data)),
                  if (!hasFlavors)
                    GestureDetector(
                      onTap: () {
                        final raw = (data['price'] as String? ?? '').replaceAll(
                          RegExp(r'[^0-9.]'),
                          '',
                        );
                        final current = double.tryParse(raw) ?? 0;
                        _editPrice(current);
                      },
                      child: _detailRow(
                        'Price Summary',
                        productPriceLabel(data),
                      ),
                    )
                  else
                    _detailRow('Price Summary', productPriceLabel(data)),

                  GestureDetector(
                    onTap: () => _manageDiscount(data),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: isDiscountActive(data)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'DISCOUNT',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(data['discountPercent'] as num).toStringAsFixed(0)}% OFF  •  Now ₱${discountedPriceValue(data)!.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                      Text(
                                        'Until ${formatDiscountDate((data['discountEnd'] as Timestamp).toDate())}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Tap to set a discount',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                          ),
                          const Icon(
                            Icons.local_offer_outlined,
                            size: 18,
                            color: primaryGreen,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasFlavors ? 'FLAVORS / VARIANTS' : 'PRODUCT INFO',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _addVariant(flavors),
                        icon: const Icon(
                          Icons.add,
                          size: 16,
                          color: primaryGreen,
                        ),
                        label: const Text(
                          'Add Variant',
                          style: TextStyle(
                            color: primaryGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (hasFlavors)
                    ...flavors.map((flavor) {
                      final int flavorStock =
                          (flavor['stock'] as num?)?.toInt() ?? 0;
                      final bool available = flavorStock > 0;
                      final StockLevel flavorStockLevel = getStockLevel(
                        flavorStock,
                      );
                      final int flavorIndex = flavors.indexOf(flavor);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final url = await pickAndUploadProductImage(
                                  context,
                                );
                                if (url == null) return;
                                final updatedFlavors =
                                    List<Map<String, dynamic>>.from(flavors);
                                updatedFlavors[flavorIndex] = {
                                  ...updatedFlavors[flavorIndex],
                                  'imageUrl': url,
                                };
                                await FirebaseFirestore.instance
                                    .collection('products')
                                    .doc(widget.productId)
                                    .update({'flavors': updatedFlavors});
                              },
                              child: Stack(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: ProductImage(
                                      imageUrl: flavor['imageUrl'] as String?,
                                      iconSize: 16,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -2,
                                    right: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: primaryGreen,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_outlined,
                                        color: Colors.white,
                                        size: 9,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _editVariantName(flavors, flavorIndex),
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            flavor['name'] as String? ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: Colors.grey.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${flavor['price'] ?? ''} • '
                                    '${flavor['stock'] ?? 0} pcs',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (available
                                            ? stockLevelColor(flavorStockLevel)
                                            : Colors.grey.shade600)
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                available
                                    ? stockLevelLabel(flavorStockLevel)
                                    : 'Out of Stock',
                                style: TextStyle(
                                  color: available
                                      ? stockLevelColor(flavorStockLevel)
                                      : Colors.grey.shade600,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'This product has no flavors or variants.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QuickRestockScreen(
                              productId: widget.productId,
                              data: data,
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primaryGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      icon: const Icon(
                        Icons.inventory_outlined,
                        color: primaryGreen,
                      ),
                      label: const Text(
                        'Update Stock',
                        style: TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class EmployeeEditProfileScreen extends StatefulWidget {
  const EmployeeEditProfileScreen({super.key});

  @override
  State<EmployeeEditProfileScreen> createState() =>
      _EmployeeEditProfileScreenState();
}

class _EmployeeEditProfileScreenState extends State<EmployeeEditProfileScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstNameController.dispose();
    _contactController.dispose();
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
          .collection('employees')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null) {
        _usernameController.text = data['username'] ?? '';
        _firstNameController.text = data['firstName'] ?? '';
        _contactController.text = data['contactNumber'] ?? '';
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

      final String username = _usernameController.text.trim();
      final String firstName = _firstNameController.text.trim();

      final existing = await FirebaseFirestore.instance
          .collection('employees')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty && existing.docs.first.id != user.uid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That username is already taken.')),
        );
        setState(() => _isSaving = false);
        return;
      }

      await user.updateDisplayName(firstName);

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(user.uid)
          .set({
            'username': username,
            'firstName': firstName,
            'contactNumber': _contactController.text.trim(),
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
                      _label('USERNAME'),
                      TextFormField(
                        controller: _usernameController,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Username is required';
                          }
                          if (v.trim().length < 3) {
                            return 'Username must be at least 3 characters';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          'e.g. zeusmario.zepp',
                          Icons.alternate_email,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('FIRST NAME'),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'First name is required'
                            : null,
                        decoration: _fieldDecoration(
                          'e.g. Zeus Mario',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('CONTACT NUMBER'),
                      TextFormField(
                        controller: _contactController,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Contact number is required';
                          }
                          final digitsOnly = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (!RegExp(r'^09\d{9}$').hasMatch(digitsOnly)) {
                            return 'Enter a valid mobile number (09XX XXX XXXX)';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          '09XX XXX XXXX',
                          Icons.phone_outlined,
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

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isProcessing = false;
  String? _username;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    _loadEmployeeInfo();
  }

  Future<void> _loadEmployeeInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(uid)
          .get();
      final data = doc.data();
      if (mounted && data != null) {
        setState(() {
          _username = data['username'] as String?;
          _fullName = data['fullName'] as String?;
        });
      }
    } catch (_) {}
  }

  Stream<Map<String, int>> _orderStatsStream() {
    return FirebaseFirestore.instance.collection('orders').snapshots().map((
      snapshot,
    ) {
      int received = snapshot.docs.length;
      int approved = 0;
      int pending = 0;
      int delivered = 0;
      for (final doc in snapshot.docs) {
        final status = (doc.data()['status'] ?? '').toString().toLowerCase();
        switch (status) {
          case 'approved':
          case 'on_the_way':
            approved++;
            break;
          case 'pending':
            pending++;
            break;
          case 'delivered':
            delivered++;
            break;
        }
      }
      return {
        'received': received,
        'approved': approved,
        'pending': pending,
        'delivered': delivered,
      };
    });
  }

  String get _displayName {
    if (_fullName != null && _fullName!.trim().isNotEmpty) return _fullName!;
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!;
    }
    return user?.email?.split('@').first ?? 'Staff';
  }

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

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

    await OneSignalService.instance.logout();
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      fadeSlideRoute(const RoleSelectionScreen()),
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
          'This will permanently delete your staff account and all associated data. '
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
    final String? password = await promptPasswordConfirmation(context);
    if (password == null || password.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(user.uid)
          .delete();
      await user.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account deleted successfully.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        fadeSlideRoute(const RoleSelectionScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = 'Could not delete account. Please try again.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Incorrect password. Account was not deleted.';
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: primaryGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials,
                          style: const TextStyle(
                            color: primaryGreen,
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
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (_username != null)
                              Text(
                                '@$_username',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12.5,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              _email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: StreamBuilder<Map<String, int>>(
                    stream: _orderStatsStream(),
                    builder: (context, snapshot) {
                      final stats =
                          snapshot.data ??
                          const {
                            'received': 0,
                            'approved': 0,
                            'pending': 0,
                            'delivered': 0,
                          };
                      return Row(
                        children: [
                          Expanded(
                            child: _EmployeeStatCard(
                              value: '${stats['received']}',
                              label: 'Received Orders',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _EmployeeStatCard(
                              value: '${stats['approved']}',
                              label: 'Approved Orders',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: StreamBuilder<Map<String, int>>(
                    stream: _orderStatsStream(),
                    builder: (context, snapshot) {
                      final stats =
                          snapshot.data ??
                          const {
                            'received': 0,
                            'approved': 0,
                            'pending': 0,
                            'delivered': 0,
                          };
                      return Row(
                        children: [
                          Expanded(
                            child: _EmployeeStatCard(
                              value: '${stats['pending']}',
                              label: 'Pending Orders',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _EmployeeStatCard(
                              value: '${stats['delivered']}',
                              label: 'Delivered Orders',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _ProfileMenuTile(
                        icon: Icons.person_outline,
                        label: 'Edit Profile',
                        subtitle: 'Update your personal info',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EmployeeEditProfileScreen(),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      _ProfileMenuTile(
                        icon: Icons.local_shipping_outlined,
                        label: 'Almares 328 Orders',
                        subtitle: 'View order history',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EmployeeMyOrdersScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _ProfileMenuTile(
                        icon: Icons.bar_chart_outlined,
                        label: 'Reports',
                        subtitle: 'Sales summary & export',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EmployeeReportsScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _ProfileMenuTile(
                        icon: Icons.notifications_outlined,
                        label: 'Orders Notification',
                        subtitle: 'View new order alerts',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EmployeeNotificationsScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: _isProcessing ? null : _logout,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Colors.redAccent,
                                  ),
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
                                onPressed: _isProcessing
                                    ? null
                                    : _deleteAccount,
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

                      if (_isProcessing)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
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

class _EmployeeStatCard extends StatelessWidget {
  final String value;
  final String label;

  const _EmployeeStatCard({required this.value, required this.label});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: primaryGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class EmployeeMyOrdersScreen extends StatefulWidget {
  const EmployeeMyOrdersScreen({super.key});

  @override
  State<EmployeeMyOrdersScreen> createState() => _EmployeeMyOrdersScreenState();
}

class _EmployeeMyOrdersScreenState extends State<EmployeeMyOrdersScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  late final TabController _tabController;

  DateTime? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  void _changeMonth(int delta) {
    setState(() {
      final base = _selectedMonth ?? DateTime.now();
      _selectedMonth = DateTime(base.year, base.month + delta);
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final List<DateTime> months = List.generate(
      24,
      (i) => DateTime(now.year, now.month - i),
    );

    final selected = await showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select Month',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.all_inclusive, color: primaryGreen),
                  title: const Text('All Months'),
                  onTap: () => Navigator.pop(context, null),
                  trailing: _selectedMonth == null
                      ? const Icon(Icons.check, color: primaryGreen)
                      : null,
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: months.length,
                    itemBuilder: (context, index) {
                      final m = months[index];
                      final bool isSelected =
                          _selectedMonth != null &&
                          _selectedMonth!.year == m.year &&
                          _selectedMonth!.month == m.month;
                      return ListTile(
                        title: Text(_monthLabel(m)),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: primaryGreen)
                            : null,
                        onTap: () => Navigator.pop(context, m),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != _selectedMonth) {
      setState(() => _selectedMonth = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Almares 328 Orders'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Pending Orders'),
            Tab(text: 'Confirmed Orders'),
            Tab(text: 'On the way Orders'),
            Tab(text: 'Delivered Orders'),
            Tab(text: 'Cancelled Orders'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                if (_selectedMonth != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.chevron_left, color: primaryGreen),
                    onPressed: () => _changeMonth(-1),
                  ),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickMonth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            color: primaryGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedMonth == null
                                ? 'All Months'
                                : _monthLabel(_selectedMonth!),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: primaryGreen,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: primaryGreen,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_selectedMonth != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.chevron_right, color: primaryGreen),
                    onPressed: () => _changeMonth(1),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _EmployeeOrderStatusList(
                  status: 'pending',
                  selectedMonth: _selectedMonth,
                ),
                _EmployeeOrderStatusList(
                  status: 'approved',
                  selectedMonth: _selectedMonth,
                ),
                _EmployeeOrderStatusList(
                  status: 'on_the_way',
                  selectedMonth: _selectedMonth,
                ),
                _EmployeeOrderStatusList(
                  status: 'delivered',
                  selectedMonth: _selectedMonth,
                ),
                _EmployeeOrderStatusList(
                  status: 'cancelled',
                  selectedMonth: _selectedMonth,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeOrderStatusList extends StatelessWidget {
  final String status;
  final DateTime? selectedMonth;

  const _EmployeeOrderStatusList({
    required this.status,
    required this.selectedMonth,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isInSelectedMonth(dynamic createdAt) {
    if (selectedMonth == null) return true;
    if (createdAt is! Timestamp) return false;
    final d = createdAt.toDate();
    return d.year == selectedMonth!.year && d.month == selectedMonth!.month;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                "Couldn't load orders: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          );
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => _isInSelectedMonth(doc.data()['createdAt']))
            .toList();

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: primaryGreen.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: primaryGreen,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No orders here',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          itemCount: docs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final orderItems = getOrderItems(data);
            final total = data['total'];
            final createdAt = data['createdAt'];
            String dateLabel = '';
            if (createdAt is Timestamp) {
              final d = createdAt.toDate();
              dateLabel = '${d.month}/${d.day}/${d.year}';
            }
            final bool awaitingConfirmation =
                (data['awaitingCustomerConfirmation'] as bool?) ?? false;
            final shortId = doc.id.substring(0, doc.id.length.clamp(0, 8));

            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EmployeeOrderDetailScreen(
                        orderId: doc.id,
                        data: data,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF0F0F0)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: ProductImage(
                          imageUrl: orderItems.isNotEmpty
                              ? orderItems.first['imageUrl'] as String?
                              : null,
                          iconSize: 22,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #$shortId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['customerName'] as String? ?? '',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              orderItems.length == 1
                                  ? (orderItems.first['productName']
                                            as String? ??
                                        '')
                                  : '${orderItems.length} items',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11.5,
                              ),
                            ),
                            if (dateLabel.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                dateLabel,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                            if (awaitingConfirmation) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Waiting for customer confirmation',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (total != null)
                        Text(
                          '₱${total.toString()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class EmployeeOrderDetailScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;

  const EmployeeOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.data,
  });

  @override
  State<EmployeeOrderDetailScreen> createState() =>
      _EmployeeOrderDetailScreenState();
}

class _EmployeeOrderDetailScreenState extends State<EmployeeOrderDetailScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isProcessing = false;
  bool _showAllItems = false;

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$minute $period';
  }

  String get _shortOrderId => widget.orderId
      .substring(0, widget.orderId.length.clamp(0, 8))
      .toUpperCase();

  Future<void> _rejectOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Order'),
        content: const Text('Are you sure you want to reject this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Yes, Reject',
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

    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({'status': 'rejected'});

      final String? userId = widget.data['userId'] as String?;
      if (userId != null) {
        await notifyCustomerOrderUpdate(
          userId: userId,
          message: 'Your order #$_shortOrderId was rejected.',
          orderId: widget.orderId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reject order: $e')));
    }
  }

  Future<void> _confirmOrder() async {
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({'status': 'approved'});

      final String? userId = widget.data['userId'] as String?;
      if (userId != null) {
        await notifyCustomerOrderUpdate(
          userId: userId,
          message: 'Your order #$_shortOrderId has been confirmed!',
          orderId: widget.orderId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not confirm order: $e')));
    }
  }

  Future<void> _markOnTheWay() async {
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
            'status': 'on_the_way',
            'awaitingCustomerConfirmation': false,
          });

      final String? userId = widget.data['userId'] as String?;
      if (userId != null) {
        await notifyCustomerOrderUpdate(
          userId: userId,
          message: 'Your order #$_shortOrderId is on its way!',
          orderId: widget.orderId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update order: $e')));
    }
  }

  Future<void> _markUndeliverable() async {
    final reason = await showUndeliverableReasonDialog(context);
    if (reason == null || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
            'status': 'undelivered',
            'deliveryIssueReason': reason,
            'awaitingCustomerConfirmation': false,
          });

      final String? userId = widget.data['userId'] as String?;
      if (userId != null) {
        await notifyCustomerOrderUpdate(
          userId: userId,
          message:
              'Your order #$_shortOrderId could not be delivered. Reason: $reason',
          orderId: widget.orderId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update order: $e')));
    }
  }

  Future<void> _markDelivered() async {
    final bool? isPaid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Is the delivery paid?'),
        content: const Text(
          'Confirm whether the customer has paid for this order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Yes',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (isPaid != true) return;

    setState(() => _isProcessing = true);

    try {
      final DateTime confirmDeadline = DateTime.now().add(
        const Duration(minutes: 10),
      );
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
            'awaitingCustomerConfirmation': true,
            'isPaid': true,
            'confirmDeadline': Timestamp.fromDate(confirmDeadline),
          });

      final String? userId = widget.data['userId'] as String?;
      if (userId != null) {
        await notifyCustomerOrderUpdate(
          userId: userId,
          message:
              'Your order #$_shortOrderId has arrived. Please confirm receipt.',
          orderId: widget.orderId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update order: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final String status = (data['status'] ?? 'pending').toString();
    final bool awaitingConfirmation =
        (data['awaitingCustomerConfirmation'] as bool?) ?? false;
    final List<Map<String, dynamic>> orderItems = getOrderItems(data);
    final double total =
        (data['total'] as num?)?.toDouble() ??
        orderItems.fold<double>(
          0,
          (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0),
        );
    final String customerName = data['customerName'] as String? ?? '';
    final String customerAddress = data['customerAddress'] as String? ?? '';

    final createdAt = data['createdAt'];
    String createdLabel = '—';
    if (createdAt is Timestamp) {
      createdLabel = _formatDate(createdAt.toDate());
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Order Details'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ORDER ID',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '#${widget.orderId.substring(0, widget.orderId.length.clamp(0, 12)).toUpperCase()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'DATE OF ORDER',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                createdLabel,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'ITEMS (${orderItems.length})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ...(_showAllItems ? orderItems.take(6) : orderItems.take(3)).map((
                item,
              ) {
                final String itemName = item['productName'] as String? ?? '';
                final String? itemFlavor = item['flavor'] as String?;
                final int itemAmount = (item['amount'] as num?)?.toInt() ?? 0;
                final double itemUnitPrice =
                    (item['unitPrice'] as num?)?.toDouble() ?? 0;
                final double itemSubtotal =
                    (item['subtotal'] as num?)?.toDouble() ??
                    (itemUnitPrice * itemAmount);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: ProductImage(
                          imageUrl: item['imageUrl'] as String?,
                          iconSize: 22,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            if (itemFlavor != null &&
                                itemFlavor.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                itemFlavor,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Qty: $itemAmount  •  ₱${itemUnitPrice.toStringAsFixed(2)} each',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₱${itemSubtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: primaryGreen,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (orderItems.length > 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _showAllItems = !_showAllItems),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: primaryGreen.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showAllItems
                                ? 'Show less'
                                : '+${(orderItems.length > 6 ? 6 : orderItems.length) - 3} more item${(orderItems.length > 6 ? 6 : orderItems.length) - 3 == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _showAllItems
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: primaryGreen,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (orderItems.length > 6)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrderItemsListScreen(
                            orderId: widget.orderId,
                            items: orderItems,
                            total: total,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'View Full Order (${orderItems.length} items)',
                          style: const TextStyle(
                            color: primaryGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward,
                          color: primaryGreen,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ORDER TOTAL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '₱${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (customerName.isNotEmpty) ...[
                Text(
                  'CUSTOMER NAME',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  customerName,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              FutureBuilder<String?>(
                future: () async {
                  final String? userId = widget.data['userId'] as String?;
                  if (userId == null) return null;
                  final doc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .get();
                  return doc.data()?['mobileNumber'] as String?;
                }(),
                builder: (context, snapshot) {
                  final String? mobile = snapshot.data;
                  if (mobile == null || mobile.trim().isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CUSTOMER PHONE',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mobile,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              if (customerAddress.isNotEmpty) ...[
                Text(
                  'DELIVERY ADDRESS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  customerAddress,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Row(
                children: [
                  Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: orderStatusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      orderStatusLabel(status),
                      style: TextStyle(
                        color: orderStatusColor(status),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              if (status == 'pending') ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _confirmOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Confirm Order',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _rejectOrder,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: const Text(
                      'Reject Order',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ] else if (status == 'approved') ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _markOnTheWay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Mark as Out for Delivery',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _markUndeliverable,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: const Text(
                      'Unable to be Delivered',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ] else if (status == 'on_the_way') ...[
                if (!awaitingConfirmation) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _markDelivered,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Order is Delivered',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _markUndeliverable,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: const Text(
                        'Unable to be Delivered',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_top,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Waiting for the customer to confirm they received the order.',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const String kEmployeeAccessCode = 'ALMARES328STAFF';
const String kEmployeeActivationCode = 'ALMARES328ACTIVATE';

const String kEmailJsServiceId = 'service_mmg4ncm';
const String kEmailJsTemplateId = 'template_szd8ssu';
const String kEmailJsPublicKey = 'D66Nq0gpzysnBwvyP';
const String kEmailJsPrivateKey = 'j5WqAXk4LvzuDs7riY8or';

String _generateOtp() {
  final random = DateTime.now().microsecondsSinceEpoch;
  final code = (random % 900000 + 100000).toString();
  return code;
}

Future<String?> sendOtpEmail({
  required String toEmail,
  required String passcode,
  required String expiryTimeLabel,
}) async {
  final uri = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'service_id': kEmailJsServiceId,
      'template_id': kEmailJsTemplateId,
      'user_id': kEmailJsPublicKey,
      'accessToken': kEmailJsPrivateKey,
      'template_params': {
        'email': toEmail,
        'passcode': passcode,
        'time': expiryTimeLabel,
      },
    }),
  );

  debugPrint('EmailJS status: ${response.statusCode}');
  debugPrint('EmailJS body: ${response.body}');

  if (response.statusCode == 200) return null;
  return '${response.statusCode}: ${response.body}';
}

Future<Map<String, dynamic>> generateAndSendActivationOtp(
  String uid,
  String email,
) async {
  final String otp = _generateOtp();
  final DateTime expiry = DateTime.now().add(const Duration(minutes: 15));

  await FirebaseFirestore.instance.collection('employees').doc(uid).set({
    'otpCode': otp,
    'otpExpiresAt': Timestamp.fromDate(expiry),
  }, SetOptions(merge: true));

  final hour = expiry.hour % 12 == 0 ? 12 : expiry.hour % 12;
  final minute = expiry.minute.toString().padLeft(2, '0');
  final period = expiry.hour >= 12 ? 'PM' : 'AM';
  final expiryLabel =
      '${expiry.month}/${expiry.day}/${expiry.year} $hour:$minute $period';

  try {
    final String? error = await sendOtpEmail(
      toEmail: email,
      passcode: otp,
      expiryTimeLabel: expiryLabel,
    );
    return {'success': error == null, 'error': error};
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

const List<Map<String, dynamic>> kProductCategories = [
  {
    'label': 'Canned Goods',
    'icon': Icons.inventory_2_outlined,
    'color': Color(0xFFFCE4D6),
  },
  {
    'label': 'Beverages',
    'icon': Icons.local_drink_outlined,
    'color': Color(0xFFD9E6F5),
  },
  {
    'label': 'Snacks',
    'icon': Icons.cookie_outlined,
    'color': Color(0xFFFAD9E0),
  },
  {
    'label': 'Rice',
    'icon': Icons.rice_bowl_outlined,
    'color': Color(0xFFF3E3F9),
  },
  {
    'label': 'Frozen Products',
    'icon': Icons.ac_unit_outlined,
    'color': Color(0xFFDDEFFA),
  },
  {
    'label': 'Instant Meals',
    'icon': Icons.ramen_dining_outlined,
    'color': Color(0xFFFFE8D6),
  },
  {
    'label': 'Bread and Dairy',
    'icon': Icons.bakery_dining_outlined,
    'color': Color(0xFFFFF3D6),
  },
  {
    'label': 'Staples',
    'icon': Icons.grain_outlined,
    'color': Color(0xFFEDE3D0),
  },
  {
    'label': 'Cooking Supplies and Essentials',
    'icon': Icons.soup_kitchen_outlined,
    'color': Color(0xFFF9E0EC),
  },
  {
    'label': 'Hair and Skin Care',
    'icon': Icons.spa_outlined,
    'color': Color(0xFFE0F5EC),
  },
  {
    'label': 'Dental and Health Care',
    'icon': Icons.medical_services_outlined,
    'color': Color(0xFFDCF0F7),
  },
  {
    'label': 'Household and Cleaning Supplies',
    'icon': Icons.cleaning_services_outlined,
    'color': Color(0xFFE3E9FC),
  },
  {
    'label': 'Others',
    'icon': Icons.category_outlined,
    'color': Color(0xFFECECEC),
  },
];

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _getDisplayName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim().split(' ').first;
    }
    if (user?.email != null) {
      return user!.email!.split('@').first;
    }
    return 'Guest';
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
              24,
              MediaQuery.of(context).padding.top + 20,
              24,
              28,
            ),
            decoration: const BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getDisplayName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CartScreen(),
                            ),
                          );
                        },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Center(
                                child: Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              Positioned(top: 2, right: 2, child: CartBadge()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllProductsScreen(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey),
                          SizedBox(width: 10),
                          Text(
                            'Search products...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: storeBannerStream(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();

              if (data == null) {
                return const SizedBox.shrink();
              }

              if (!isBannerCurrentlyValid(data)) {
                if ((data['scheduleEnd'] as Timestamp?) != null) {
                  deleteStoreBanner();
                }
                return const SizedBox.shrink();
              }

              final String offer = data['offer'] as String? ?? '';
              final String description = data['description'] as String? ?? '';
              final String? bannerImage = data['imageUrl'] as String?;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onLongPress: () async {
                        await seedProductCatalog();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Product catalog seeded.'),
                            ),
                          );
                        }
                      },
                      child: Container(
                        height: 130,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCEBDD),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: bannerImage != null
                                  ? ProductImage(
                                      imageUrl: bannerImage,
                                      iconSize: 40,
                                      borderRadius: BorderRadius.circular(18),
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.image_outlined,
                                        size: 40,
                                        color: primaryGreen.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                    ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.45),
                                    Colors.transparent,
                                  ],
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              bottom: 16,
                              right: 18,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SPECIAL OFFER',
                                    style: TextStyle(
                                      color: Colors.greenAccent.shade100,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    offer,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Categories',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CategoriesPlaceholderTab(),
                      ),
                    );
                  },
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: primaryGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 94,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: kProductCategories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final category = kProductCategories[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategoryProductsScreen(
                          category: category['label'] as String,
                        ),
                      ),
                    );
                  },
                  child: SizedBox(
                    width: 68,
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: category['color'] as Color,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            category['icon'] as IconData,
                            color: primaryGreen,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          category['label'] as String,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('featured', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              final featured = snapshot.data?.docs ?? [];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Featured Products',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const FeaturedProductsScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'See all',
                            style: TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (featured.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Text(
                          '--- No featured products ---',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 260,
                      child: FutureBuilder<Set<String>>(
                        future: fetchBestSellingProductIds(),
                        builder: (context, bestSellingSnapshot) {
                          final bestSellingIds = bestSellingSnapshot.data ?? {};
                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: featured.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final doc = featured[index];
                              final product = {...doc.data(), 'id': doc.id};
                              return SizedBox(
                                width: 150,
                                child: _ProductCard(
                                  product: product,
                                  isBestSelling: bestSellingIds.contains(
                                    doc.id,
                                  ),
                                  onImageTap: () => showProductOptions(
                                    context,
                                    product: product,
                                    mode: 'order',
                                  ),
                                  onAddTap: () => showProductOptions(
                                    context,
                                    product: product,
                                    mode: 'checkout',
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class FeaturedProductsScreen extends StatelessWidget {
  const FeaturedProductsScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Featured Products'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AllProductsScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.grid_view_rounded,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'Browse All',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('featured', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star_border,
                        color: primaryGreen,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '-- No more featured products --',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllProductsScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primaryGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(
                        Icons.grid_view_rounded,
                        color: primaryGreen,
                        size: 18,
                      ),
                      label: const Text(
                        'Browse All Products',
                        style: TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final products = docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _ProductCard(
                product: product,
                onImageTap: () => showProductOptions(
                  context,
                  product: product,
                  mode: 'order',
                ),
                onAddTap: () => showProductOptions(
                  context,
                  product: product,
                  mode: 'checkout',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

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

enum ProductSortOption {
  nameAsc,
  nameDesc,
  priceLowHigh,
  priceHighLow,
  category,
}

double _extractSortPrice(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map(
          (f) =>
              double.tryParse(
                (f['price'] as String? ?? '').replaceAll(
                  RegExp(r'[^0-9.]'),
                  '',
                ),
              ) ??
              0,
        )
        .where((p) => p > 0)
        .toList();
    if (prices.isNotEmpty) {
      prices.sort();
      return prices.first;
    }
  }
  final raw = (product['price'] as String? ?? '').replaceAll(
    RegExp(r'[^0-9.]'),
    '',
  );
  return double.tryParse(raw) ?? 0;
}

List<Map<String, dynamic>> sortProducts(
  List<Map<String, dynamic>> products,
  ProductSortOption option,
) {
  final sorted = List<Map<String, dynamic>>.from(products);
  switch (option) {
    case ProductSortOption.nameAsc:
      sorted.sort(
        (a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo(
          (b['name'] as String? ?? '').toLowerCase(),
        ),
      );
      break;
    case ProductSortOption.nameDesc:
      sorted.sort(
        (a, b) => (b['name'] as String? ?? '').toLowerCase().compareTo(
          (a['name'] as String? ?? '').toLowerCase(),
        ),
      );
      break;
    case ProductSortOption.priceLowHigh:
      sorted.sort(
        (a, b) => _extractSortPrice(a).compareTo(_extractSortPrice(b)),
      );
      break;
    case ProductSortOption.priceHighLow:
      sorted.sort(
        (a, b) => _extractSortPrice(b).compareTo(_extractSortPrice(a)),
      );
      break;
    case ProductSortOption.category:
      sorted.sort(
        (a, b) => (a['category'] as String? ?? '').toLowerCase().compareTo(
          (b['category'] as String? ?? '').toLowerCase(),
        ),
      );
      break;
  }
  return sorted;
}

String sortOptionLabel(ProductSortOption option) {
  switch (option) {
    case ProductSortOption.nameAsc:
      return 'Name (A-Z)';
    case ProductSortOption.nameDesc:
      return 'Name (Z-A)';
    case ProductSortOption.priceLowHigh:
      return 'Price (Low to High)';
    case ProductSortOption.priceHighLow:
      return 'Price (High to Low)';
    case ProductSortOption.category:
      return 'Category';
  }
}

bool isDiscountActive(Map<String, dynamic> product) {
  final percent = product['discountPercent'];
  final start = product['discountStart'];
  final end = product['discountEnd'];
  if (percent == null || percent is! num || percent <= 0) return false;
  if (start is! Timestamp || end is! Timestamp) return false;
  final now = DateTime.now();
  return now.isAfter(start.toDate()) && now.isBefore(end.toDate());
}

double? discountedPriceValue(Map<String, dynamic> product) {
  if (!isDiscountActive(product)) return null;
  final double base = _extractSortPrice(product);
  final double percent = (product['discountPercent'] as num).toDouble();
  return base * (1 - percent / 100);
}

String formatDiscountDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// If a discount has passed its end date, clears it from Firestore so the
/// product returns to its normal price. Safe to call repeatedly.
Future<void> checkAndExpireDiscount(
  String? productId,
  Map<String, dynamic> data,
) async {
  if (productId == null) return;
  final percent = data['discountPercent'];
  final end = data['discountEnd'];
  if (percent == null || end is! Timestamp) return;
  if (DateTime.now().isBefore(end.toDate())) return;

  await FirebaseFirestore.instance
      .collection('products')
      .doc(productId)
      .update({
        'discountPercent': FieldValue.delete(),
        'discountStart': FieldValue.delete(),
        'discountEnd': FieldValue.delete(),
      });
}

String productPriceLabel(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    final prices = flavors
        .map((f) {
          final raw = (f['price'] as String? ?? '').replaceAll(
            RegExp(r'[^0-9.]'),
            '',
          );
          return double.tryParse(raw) ?? 0;
        })
        .where((p) => p > 0)
        .toList();
    if (prices.isNotEmpty) {
      prices.sort();
      final low = prices.first;
      final high = prices.last;
      if (low == high) return '₱${low.toStringAsFixed(2)}';
      return 'From ₱${low.toStringAsFixed(2)}';
    }
  }
  return product['price'] as String? ?? '₱0.00';
}

enum StockLevel { critical, low, enough }

StockLevel getStockLevel(int totalStock) {
  if (totalStock <= 10) return StockLevel.critical;
  if (totalStock <= 30) return StockLevel.low;
  return StockLevel.enough;
}

int extractTotalStock(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (flavors.isNotEmpty) {
    return flavors.fold<int>(
      0,
      (sum, f) => sum + ((f['stock'] as num?)?.toInt() ?? 0),
    );
  }
  return (product['stockCount'] as num?)?.toInt() ?? 0;
}

String stockLevelLabel(StockLevel level) {
  switch (level) {
    case StockLevel.critical:
      return 'Critically Low';
    case StockLevel.low:
      return 'Low Stock';
    case StockLevel.enough:
      return 'Enough Stock';
  }
}

Color stockLevelColor(StockLevel level) {
  switch (level) {
    case StockLevel.critical:
      return Colors.redAccent;
    case StockLevel.low:
      return Colors.orange;
    case StockLevel.enough:
      return const Color(0xFF2E6B3E);
  }
}

String productStockLabel(Map<String, dynamic> product) {
  final flavors =
      (product['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final int total = flavors.isNotEmpty
      ? flavors.fold<int>(
          0,
          (sum, f) => sum + ((f['stock'] as num?)?.toInt() ?? 0),
        )
      : (product['stockCount'] as num?)?.toInt() ?? 0;
  return '$total pcs available';
}

const String kCloudinaryCloudName = 'h5291fss';
const String kCloudinaryUploadPreset = 'almares_products';

Future<String?> uploadImageToCloudinary(XFile imageFile) async {
  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/image/upload',
  );
  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = kCloudinaryUploadPreset
    ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['secure_url'] as String?;
  }
  return null;
}

Future<String?> pickAndUploadProductImage(BuildContext context) async {
  final ImageSource? source = await showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add Product Photo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt_outlined,
                    color: Color(0xFF2E6B3E),
                  ),
                  title: const Text('Take Photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF2E6B3E),
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (source == null) return null;

  final ImagePicker picker = ImagePicker();
  final XFile? file = await picker.pickImage(
    source: source,
    imageQuality: 70,
    maxWidth: 1080,
  );

  if (file == null) return null;
  if (!context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        const Center(child: CircularProgressIndicator(color: Colors.white)),
  );

  String? url;
  try {
    url = await uploadImageToCloudinary(file);
  } catch (_) {
    url = null;
  }

  if (context.mounted) {
    Navigator.pop(context);
  }

  if (url == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not upload photo. Please try again.'),
      ),
    );
  }

  return url;
}

class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double iconSize;
  final BorderRadius borderRadius;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.iconSize = 32,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: borderRadius,
        ),
        child: Center(
          child: Icon(Icons.image_outlined, color: Colors.grey, size: iconSize),
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: const Color(0xFFF4F4F4),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F4),
            borderRadius: borderRadius,
          ),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.grey,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> addCustomerNotification({
  required String userId,
  required String message,
  String? orderId,
}) async {
  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .get();
  final prefs = userDoc.data()?['notificationPrefs'] as Map<String, dynamic>?;
  final bool orderUpdatesEnabled = (prefs?['orderUpdates'] as bool?) ?? true;
  if (!orderUpdatesEnabled) return;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('notifications')
      .add({
        'message': message,
        'orderId': orderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
}

Future<void> notifyCustomerOrderUpdate({
  required String userId,
  required String message,
  String? orderId,
}) async {
  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .get();
  final prefs = userDoc.data()?['notificationPrefs'] as Map<String, dynamic>?;
  final bool orderUpdatesEnabled = (prefs?['orderUpdates'] as bool?) ?? true;

  await addCustomerNotification(
    userId: userId,
    message: message,
    orderId: orderId,
  );

  if (orderUpdatesEnabled) {
    await sendPushNotification(
      toFirebaseUid: userId,
      message: message,
      orderId: orderId,
    );
  }
}

Future<void> addEmployeeOrderNotification({
  required String message,
  String? orderId,
}) async {
  await FirebaseFirestore.instance.collection('employeeNotifications').add({
    'message': message,
    'orderId': orderId,
    'read': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Stream<DocumentSnapshot<Map<String, dynamic>>> storeBannerStream() {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('storeBanner')
      .snapshots();
}

Future<void> saveStoreBanner({
  required String offer,
  required String description,
  String? imageUrl,
  DateTime? scheduleStart,
  DateTime? scheduleEnd,
}) async {
  await FirebaseFirestore.instance
      .collection('settings')
      .doc('storeBanner')
      .set({
        'offer': offer,
        'description': description,
        'imageUrl': imageUrl,
        'scheduleStart': scheduleStart != null
            ? Timestamp.fromDate(scheduleStart)
            : null,
        'scheduleEnd': scheduleEnd != null
            ? Timestamp.fromDate(scheduleEnd)
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

bool isBannerCurrentlyValid(Map<String, dynamic> data) {
  final scheduleStart = data['scheduleStart'];
  final scheduleEnd = data['scheduleEnd'];
  final now = DateTime.now();
  if (scheduleStart is Timestamp && now.isBefore(scheduleStart.toDate()))
    return false;
  if (scheduleEnd is Timestamp && now.isAfter(scheduleEnd.toDate()))
    return false;
  return true;
}

Future<void> deleteStoreBanner() async {
  await FirebaseFirestore.instance
      .collection('settings')
      .doc('storeBanner')
      .delete();
}

Future<void> setProductFeatured(String productId, bool featured) async {
  await FirebaseFirestore.instance.collection('products').doc(productId).update(
    {'featured': featured},
  );
}

Future<String?> promptPasswordConfirmation(BuildContext context) async {
  final passwordController = TextEditingController();
  bool obscure = true;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Confirm Your Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'For your security, please enter your password to continue.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (passwordController.text.isEmpty) return;
                  Navigator.pop(context, passwordController.text);
                },
                child: const Text(
                  'Confirm',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> deleteProduct(String productId) async {
  await FirebaseFirestore.instance
      .collection('products')
      .doc(productId)
      .delete();
}

const List<String> kUndeliverableReasons = [
  'Customer not available / unreachable',
  'Incorrect or incomplete address',
  'Customer refused the delivery',
  'Item out of stock or damaged',
  'Unsafe delivery area / weather conditions',
];

Future<String?> showUndeliverableReasonDialog(BuildContext context) async {
  String? selectedReason;
  final customController = TextEditingController();
  bool useCustom = false;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Unable to be Delivered'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add reason or feedback:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  ...kUndeliverableReasons.map((reason) {
                    return RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        reason,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      value: reason,
                      groupValue: useCustom ? null : selectedReason,
                      onChanged: (value) {
                        setDialogState(() {
                          selectedReason = value;
                          useCustom = false;
                        });
                      },
                    );
                  }),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Other (specify)',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    value: true,
                    groupValue: useCustom,
                    onChanged: (value) {
                      setDialogState(() => useCustom = true);
                    },
                  ),
                  if (useCustom) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: customController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Type your reason here',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  final String? finalReason = useCustom
                      ? (customController.text.trim().isEmpty
                            ? null
                            : customController.text.trim())
                      : selectedReason;
                  if (finalReason == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select or enter a reason.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, finalReason);
                },
                child: const Text(
                  'Submit',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool> confirmDeleteProduct(
  BuildContext context,
  String productName,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove Product'),
      content: Text(
        'Are you sure you want to remove "$productName"? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Remove',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}

List<Map<String, dynamic>> getOrderItems(Map<String, dynamic> data) {
  final rawItems = data['items'] as List?;
  if (rawItems != null && rawItems.isNotEmpty) {
    return rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  if (data['productName'] != null) {
    return [
      {
        'productId': data['productId'],
        'productName': data['productName'],
        'imageUrl': data['imageUrl'],
        'flavor': data['flavor'],
        'amount': data['amount'],
        'unitPrice': data['unitPrice'],
        'subtotal': data['total'],
      },
    ];
  }

  return [];
}

Color orderStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'delivered':
      return const Color(0xFF2E6B3E);
    case 'on_the_way':
      return Colors.blue;
    case 'approved':
      return Colors.teal;
    case 'pending':
      return Colors.orange;
    case 'rejected':
    case 'cancelled':
    case 'undelivered':
      return Colors.redAccent;
    default:
      return Colors.grey;
  }
}

String orderStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'on_the_way':
      return 'On the Way';
    case 'pending':
      return 'Pending';
    case 'approved':
      return 'Approved';
    case 'delivered':
      return 'Delivered';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'undelivered':
      return 'Unable to Deliver';
    default:
      return status;
  }
}

Future<void> checkAndAutoConfirmOrder(
  String orderId,
  Map<String, dynamic> data,
) async {
  final bool awaiting =
      (data['awaitingCustomerConfirmation'] as bool?) ?? false;
  final Timestamp? deadline = data['confirmDeadline'] as Timestamp?;
  if (!awaiting || deadline == null) return;
  if (DateTime.now().isBefore(deadline.toDate())) return;

  await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
    'status': 'delivered',
    'awaitingCustomerConfirmation': false,
    'autoConfirmed': true,
  });
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onImageTap;
  final VoidCallback onAddTap;
  final bool isBestSelling;

  const _ProductCard({
    required this.product,
    required this.onImageTap,
    required this.onAddTap,
    this.isBestSelling = false,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final String name = product['name'] as String? ?? '';
    final String stock = productStockLabel(product);
    final String price = productPriceLabel(product);
    final bool isOutOfStock = extractTotalStock(product) <= 0;
    final bool onSale = isDiscountActive(product);
    final double? discountedPrice = onSale
        ? discountedPriceValue(product)
        : null;

    // Fire-and-forget cleanup: clears the discount once it has expired.
    checkAndExpireDiscount(product['id'] as String?, product);

    return Opacity(
      opacity: isOutOfStock ? 0.5 : 1.0,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isOutOfStock ? null : onImageTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF0F0F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColorFiltered(
                        colorFilter: isOutOfStock
                            ? const ColorFilter.matrix([
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ])
                            : const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.multiply,
                              ),
                        child: ProductImage(
                          imageUrl: product['imageUrl'] as String?,
                          iconSize: 32,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                      ),
                      if (isBestSelling && !isOutOfStock)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  color: Colors.white,
                                  size: 11,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'BEST-SELLING',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (onSale && !isOutOfStock)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(product['discountPercent'] as num).toStringAsFixed(0)}% OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          extractTotalStock(product) <= 0
                              ? 'Out of Stock'
                              : stock,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: extractTotalStock(product) <= 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: extractTotalStock(product) <= 0
                                ? Colors.redAccent
                                : Colors.grey,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: onSale
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          price,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey.shade500,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                        Text(
                                          '₱${discountedPrice!.toStringAsFixed(2)}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      price,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: primaryGreen,
                                      ),
                                    ),
                            ),
                            Material(
                              color: primaryGreen,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: onAddTap,
                                child: const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

class CategoriesPlaceholderTab extends StatefulWidget {
  const CategoriesPlaceholderTab({super.key});

  @override
  State<CategoriesPlaceholderTab> createState() =>
      _CategoriesPlaceholderTabState();
}

class _CategoriesPlaceholderTabState extends State<CategoriesPlaceholderTab> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSort() async {
    final selected = await showModalBottomSheet<ProductSortOption>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sort By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...ProductSortOption.values.map((option) {
                    final bool isSelected = _sortOption == option;
                    return ListTile(
                      title: Text(sortOptionLabel(option)),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: primaryGreen)
                          : null,
                      onTap: () => Navigator.pop(context, option),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _sortOption = selected);
  }

  @override
  Widget build(BuildContext context) {
    final bool isSearching = _query.trim().isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Categories',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickSort,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: primaryGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.sort,
                              color: primaryGreen,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sortOptionLabel(_sortOption),
                              style: const TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: isSearching
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!isSearching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Material(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllProductsScreen(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.grid_view_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Browse All Products',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'See everything in one place',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: isSearching
                    ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('products')
                            .snapshots(),
                        builder: (context, snapshot) {
                          final allDocs = snapshot.data?.docs ?? [];
                          final matches = allDocs
                              .map((doc) => {...doc.data(), 'id': doc.id})
                              .where(
                                (p) => (p['name'] as String? ?? '')
                                    .toLowerCase()
                                    .contains(_query.trim().toLowerCase()),
                              )
                              .toList();
                          final sorted = sortProducts(matches, _sortOption);

                          if (sorted.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      color: Colors.grey.shade400,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No products found for "$_query"',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return GridView.builder(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              0,
                              20,
                              20 + MediaQuery.of(context).padding.bottom,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: 0.62,
                                ),
                            itemCount: sorted.length,
                            itemBuilder: (context, index) {
                              final product = sorted[index];
                              return _ProductCard(
                                product: product,
                                onImageTap: () => showProductOptions(
                                  context,
                                  product: product,
                                  mode: 'order',
                                ),
                                onAddTap: () => showProductOptions(
                                  context,
                                  product: product,
                                  mode: 'checkout',
                                ),
                              );
                            },
                          );
                        },
                      )
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          20 + MediaQuery.of(context).padding.bottom,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 1.3,
                            ),
                        itemCount: kProductCategories.length,
                        itemBuilder: (context, index) {
                          final category = kProductCategories[index];
                          return Material(
                            color: category['color'] as Color,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        CategoryProductsScreen(
                                          category: category['label'] as String,
                                        ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      category['icon'] as IconData,
                                      color: primaryGreen,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      category['label'] as String,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSort() async {
    final selected = await showModalBottomSheet<ProductSortOption>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sort By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...ProductSortOption.values.map((option) {
                    final bool isSelected = _sortOption == option;
                    return ListTile(
                      title: Text(sortOptionLabel(option)),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: primaryGreen)
                          : null,
                      onTap: () => Navigator.pop(context, option),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _sortOption = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('All Products'),
        actions: [
          IconButton(
            onPressed: _pickSort,
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search all products...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data?.docs ?? [];
                final products = allDocs
                    .map((doc) => {...doc.data(), 'id': doc.id})
                    .toList();

                final filtered = _query.trim().isEmpty
                    ? products
                    : products
                          .where(
                            (p) => (p['name'] as String? ?? '')
                                .toLowerCase()
                                .contains(_query.trim().toLowerCase()),
                          )
                          .toList();

                final sorted = sortProducts(filtered, _sortOption);

                if (sorted.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _query.isEmpty
                                ? Icons.inventory_2_outlined
                                : Icons.search_off,
                            color: primaryGreen.withValues(alpha: 0.4),
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'No products available yet'
                                : 'No products found for "$_query"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return FutureBuilder<Set<String>>(
                  future: fetchBestSellingProductIds(),
                  builder: (context, bestSellingSnapshot) {
                    final bestSellingIds = bestSellingSnapshot.data ?? {};
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        20 + MediaQuery.of(context).padding.bottom,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.62,
                          ),
                      itemCount: sorted.length,
                      itemBuilder: (context, index) {
                        final product = sorted[index];
                        return _ProductCard(
                          product: product,
                          isBestSelling: bestSellingIds.contains(product['id']),
                          onImageTap: () => showProductOptions(
                            context,
                            product: product,
                            mode: 'order',
                          ),
                          onAddTap: () => showProductOptions(
                            context,
                            product: product,
                            mode: 'checkout',
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryProductsScreen extends StatefulWidget {
  final String category;

  const CategoryProductsScreen({super.key, required this.category});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  Future<void> _pickSort() async {
    final selected = await showModalBottomSheet<ProductSortOption>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sort By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...ProductSortOption.values
                      .where((o) => o != ProductSortOption.category)
                      .map((option) {
                        final bool isSelected = _sortOption == option;
                        return ListTile(
                          title: Text(sortOptionLabel(option)),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: primaryGreen)
                              : null,
                          onTap: () => Navigator.pop(context, option),
                        );
                      }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _sortOption = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: Text(widget.category),
        actions: [
          IconButton(
            onPressed: _pickSort,
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: widget.category)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: primaryGreen,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No products in this category yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final products = docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
          final sorted = sortProducts(products, _sortOption);

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final product = sorted[index];
              return _ProductCard(
                product: product,
                onImageTap: () => showProductOptions(
                  context,
                  product: product,
                  mode: 'order',
                ),
                onAddTap: () => showProductOptions(
                  context,
                  product: product,
                  mode: 'checkout',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class OrdersPlaceholderTab extends StatelessWidget {
  const OrdersPlaceholderTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const OrdersListView();
  }
}

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('My Orders'),
      ),
      body: const OrdersListView(),
    );
  }
}

class OrdersListView extends StatefulWidget {
  const OrdersListView({super.key});

  @override
  State<OrdersListView> createState() => _OrdersListViewState();
}

class _OrdersListViewState extends State<OrdersListView> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isClearing = false;

  String? _selectedStatus;

  static const List<Map<String, String>> _statusOptions = [
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'approved', 'label': 'Approved'},
    {'value': 'on_the_way', 'label': 'On Its Way'},
    {'value': 'delivered', 'label': 'Delivered'},
    {'value': 'cancelled', 'label': 'Cancelled'},
    {'value': 'undelivered', 'label': 'Unable to Deliver'},
  ];

  Color _statusColor(String status) => orderStatusColor(status);

  Future<void> _pickStatus() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Filter by Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.all_inclusive,
                      color: primaryGreen,
                    ),
                    title: const Text('All'),
                    trailing: _selectedStatus == null
                        ? const Icon(Icons.check, color: primaryGreen)
                        : null,
                    onTap: () => Navigator.pop(context, null),
                  ),
                  const Divider(height: 1),
                  ..._statusOptions.map((option) {
                    final bool isSelected = _selectedStatus == option['value'];
                    return ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: orderStatusColor(option['value']!),
                      ),
                      title: Text(option['label']!),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: primaryGreen)
                          : null,
                      onTap: () => Navigator.pop(context, option['value']),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != _selectedStatus) {
      setState(() => _selectedStatus = selected);
    }
  }

  String get _selectedStatusLabel {
    if (_selectedStatus == null) return 'All';
    return _statusOptions.firstWhere(
      (o) => o['value'] == _selectedStatus,
    )['label']!;
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  bool _isInSelectedMonth(dynamic createdAt) {
    if (createdAt is! Timestamp) return false;
    final d = createdAt.toDate();
    return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
  }

  Future<void> _clearCancelledHistory(
    List<QueryDocumentSnapshot> cancelledDocs,
  ) async {
    if (cancelledDocs.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear History'),
        content: Text(
          'This will permanently delete ${cancelledDocs.length} cancelled '
          'order${cancelledDocs.length == 1 ? '' : 's'} from '
          '${_monthLabel(_selectedMonth)}. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear History',
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

    setState(() => _isClearing = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in cancelledDocs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cancelled order history cleared.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not clear history: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(child: Text('Please log in to view your orders.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Couldn't load orders",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];

        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bool monthMatch = _isInSelectedMonth(data['createdAt']);
          final bool statusMatch =
              _selectedStatus == null ||
              (data['status'] ?? '').toString().toLowerCase() ==
                  _selectedStatus;
          return monthMatch && statusMatch;
        }).toList();

        for (final doc in allDocs) {
          checkAndAutoConfirmOrder(doc.id, doc.data() as Map<String, dynamic>);
        }

        final cancelledDocs = filteredDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? '').toString().toLowerCase() == 'cancelled';
        }).toList();

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.white,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          child: Column(
            children: [
              SafeArea(
                top: true,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    color: primaryGreen,
                                  ),
                                  onPressed: () => _changeMonth(-1),
                                ),
                                Expanded(
                                  child: Text(
                                    _monthLabel(_selectedMonth),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    color: primaryGreen,
                                  ),
                                  onPressed: () => _changeMonth(1),
                                ),
                              ],
                            ),
                          ),
                          if (cancelledDocs.isNotEmpty)
                            TextButton.icon(
                              onPressed: _isClearing
                                  ? null
                                  : () => _clearCancelledHistory(cancelledDocs),
                              icon: _isClearing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.redAccent,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.delete_sweep_outlined,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                              label: const Text(
                                'Clear History',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final double monthTotal = filteredDocs.fold<double>(
                            0,
                            (sum, doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final String docStatus = (data['status'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              if (docStatus == 'cancelled' ||
                                  docStatus == 'rejected' ||
                                  docStatus == 'undelivered') {
                                return sum;
                              }
                              final total = data['total'];
                              return sum +
                                  ((total is num) ? total.toDouble() : 0);
                            },
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total this month',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12.5,
                                  ),
                                ),
                                Text(
                                  '₱${monthTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: _pickStatus,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: primaryGreen.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.filter_list,
                                  color: primaryGreen,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedStatusLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: primaryGreen,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: primaryGreen,
                                  size: 16,
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

              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: primaryGreen.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: primaryGreen,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                allDocs.isEmpty
                                    ? 'No orders yet'
                                    : 'No orders in ${_monthLabel(_selectedMonth)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                allDocs.isEmpty
                                    ? 'Your order history will appear here.'
                                    : 'Try a different month.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          20 + MediaQuery.of(context).padding.bottom,
                        ),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final data =
                              filteredDocs[index].data()
                                  as Map<String, dynamic>;
                          final orderItems = getOrderItems(data);
                          final status = (data['status'] ?? 'pending')
                              .toString();
                          final total = data['total'];
                          final createdAt = data['createdAt'];
                          String dateLabel = '';
                          if (createdAt is Timestamp) {
                            final d = createdAt.toDate();
                            dateLabel = '${d.month}/${d.day}/${d.year}';
                          }
                          final orderId = filteredDocs[index].id;
                          final shortId = orderId.substring(
                            0,
                            orderId.length.clamp(0, 8),
                          );
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrderDetailsScreen(
                                      orderId: orderId,
                                      data: data,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFF0F0F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: ProductImage(
                                        imageUrl: orderItems.isNotEmpty
                                            ? orderItems.first['imageUrl']
                                                  as String?
                                            : null,
                                        iconSize: 22,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Order #$shortId',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            orderItems.length == 1
                                                ? (orderItems.first['productName']
                                                          as String? ??
                                                      '')
                                                : '${orderItems.length} items',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (dateLabel.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              dateLabel,
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (total != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: Text(
                                          '₱${total.toString()}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(
                                          status,
                                        ).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        orderStatusLabel(status),
                                        style: TextStyle(
                                          color: _statusColor(status),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConfirmationCountdownBanner extends StatefulWidget {
  final DateTime deadline;
  const _ConfirmationCountdownBanner({required this.deadline});

  @override
  State<_ConfirmationCountdownBanner> createState() =>
      _ConfirmationCountdownBannerState();
}

class _ConfirmationCountdownBannerState
    extends State<_ConfirmationCountdownBanner> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.deadline.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final newRemaining = widget.deadline.difference(DateTime.now());
      if (mounted) {
        setState(
          () => _remaining = newRemaining.isNegative
              ? Duration.zero
              : newRemaining,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int minutes = _remaining.inMinutes;
    final int seconds = _remaining.inSeconds % 60;
    final bool urgent = _remaining.inMinutes < 5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (urgent ? Colors.orange : Colors.blue).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (urgent ? Colors.orange : Colors.blue).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            color: urgent ? Colors.orange.shade800 : Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _remaining == Duration.zero
                  ? 'Confirmation window has ended. This order will be auto-confirmed shortly.'
                  : '${minutes}m ${seconds.toString().padLeft(2, '0')}s left to confirm your order.',
              style: TextStyle(
                color: urgent ? Colors.orange.shade800 : Colors.blue.shade700,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.data,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _TrackingStep extends StatelessWidget {
  final String label;
  final bool reached;
  final bool isLast;

  const _TrackingStep({
    required this.label,
    required this.reached,
    required this.isLast,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final Color color = reached ? primaryGreen : Colors.grey.shade300;
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 3,
                  color: label == 'Pending' ? Colors.transparent : color,
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(height: 3, color: Colors.grey.shade300),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
              color: reached ? primaryGreen : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isCancelling = false;
  bool _isConfirmingReceipt = false;
  final bool _showAllItems = false;

  Future<void> _confirmReceived() async {
    setState(() => _isConfirmingReceipt = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
            'status': 'delivered',
            'awaitingCustomerConfirmation': false,
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Thanks for confirming! Order marked as delivered.',
          ),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not confirm: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isConfirmingReceipt = false);
    }
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Order'),
        content: const Text(
          'Are you sure you want to cancel this order? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Yes, Cancel',
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

    setState(() => _isCancelling = true);

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({'status': 'cancelled'});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Order cancelled.'),
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
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not cancel order. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$minute $period';
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toString();
    final bool awaitingConfirmation =
        (data['awaitingCustomerConfirmation'] as bool?) ?? false;
    final List<Map<String, dynamic>> orderItems = getOrderItems(data);
    final double total =
        (data['total'] as num?)?.toDouble() ??
        orderItems.fold<double>(
          0,
          (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0),
        );
    final String customerName = data['customerName'] as String? ?? '';
    final String customerAddress = data['customerAddress'] as String? ?? '';

    final createdAt = data['createdAt'];
    String createdLabel = '—';
    if (createdAt is Timestamp) {
      createdLabel = _formatDate(createdAt.toDate());
    }

    final estimatedDelivery = data['estimatedDelivery'];
    String deliveryLabel = '—';
    if (estimatedDelivery is Timestamp) {
      deliveryLabel = _formatDate(estimatedDelivery.toDate());
    }

    final bool isRejectedOrCancelled =
        status == 'rejected' ||
        status == 'cancelled' ||
        status == 'undelivered';
    final String? deliveryIssueReason = data['deliveryIssueReason'] as String?;
    const stageOrder = ['pending', 'approved', 'on_the_way', 'delivered'];
    final int currentStageIndex = stageOrder.indexOf(status);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isRejectedOrCancelled) ...[
              Row(
                children: [
                  _TrackingStep(
                    label: 'Pending',
                    reached: currentStageIndex >= 0,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: 'Confirmed',
                    reached: currentStageIndex >= 1,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: 'On the Way',
                    reached: currentStageIndex >= 2,
                    isLast: false,
                  ),
                  _TrackingStep(
                    label: 'Delivered',
                    reached: currentStageIndex >= 3,
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
            if (status == 'undelivered' && deliveryIssueReason != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Unable to be Delivered',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reason: $deliveryIssueReason',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.redAccent.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if ((data['awaitingCustomerConfirmation'] as bool?) == true &&
                data['confirmDeadline'] is Timestamp) ...[
              _ConfirmationCountdownBanner(
                deadline: (data['confirmDeadline'] as Timestamp).toDate(),
              ),
              const SizedBox(height: 20),
            ],
            if (status == 'delivered' && (data['isPaid'] as bool?) == true) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: primaryGreen, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Paid and Delivered',
                      style: TextStyle(
                        color: primaryGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'ORDER ID',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '#${widget.orderId.substring(0, widget.orderId.length.clamp(0, 12)).toUpperCase()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'DATE OF ORDER',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              createdLabel,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'ITEMS (${orderItems.length})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...(_showAllItems ? orderItems.take(6) : orderItems.take(3)).map(
              (item) => OrderItemCard(item: item),
            ),
            if (orderItems.length > 6)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderItemsListScreen(
                          orderId: widget.orderId,
                          items: orderItems,
                          total: total,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'View Full Order (${orderItems.length} items)',
                        style: const TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        color: primaryGreen,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ORDER TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (customerName.isNotEmpty) ...[
              Text(
                'CUSTOMER NAME',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                customerName,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (customerAddress.isNotEmpty) ...[
              Text(
                'DELIVERY ADDRESS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                customerAddress,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],

            Text(
              'ESTIMATED DELIVERY',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              deliveryLabel,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Text(
                  'STATUS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: orderStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    orderStatusLabel(status),
                    style: TextStyle(
                      color: orderStatusColor(status),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            if (status == 'on_the_way') ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (awaitingConfirmation && !_isConfirmingReceipt)
                      ? _confirmReceived
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: awaitingConfirmation
                        ? primaryGreen
                        : Colors.grey.shade300,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: awaitingConfirmation ? 3 : 0,
                  ),
                  child: _isConfirmingReceipt
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Confirm Received Order',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: awaitingConfirmation
                                ? Colors.white
                                : Colors.grey.shade500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 3,
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            if (status.toLowerCase() == 'pending') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _isCancelling ? null : _cancelOrder,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _isCancelling
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.redAccent,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Cancel Order',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                ),
              ),
            ],
            SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
          ],
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
        title: const Text('Order Details'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? widget.data;
          checkAndAutoConfirmOrder(widget.orderId, data);
          return _buildBody(context, data);
        },
      ),
    );
  }
}

class CartPlaceholderTab extends StatelessWidget {
  const CartPlaceholderTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SimplePlaceholderTab(
      icon: Icons.shopping_cart_outlined,
      title: 'My Cart',
      message: 'Items you add to your cart will appear here.',
    );
  }
}

class _SimplePlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SimplePlaceholderTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primaryGreen, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final String? password = await promptPasswordConfirmation(context);
    if (password == null || password.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

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
        message = 'Incorrect password. Account was not deleted.';
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
                  _ProfileMenuTile(
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
                  _ProfileMenuTile(
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
                  _ProfileMenuTile(
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
                  _ProfileMenuTile(
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
                  _ProfileMenuTile(
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

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback? onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  }) : destructive = false;

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final Color color = destructive ? Colors.redAccent : Colors.black87;
    final Color iconBg = destructive
        ? Colors.redAccent.withValues(alpha: 0.08)
        : primaryGreen.withValues(alpha: 0.08);
    final Color iconColor = destructive ? Colors.redAccent : primaryGreen;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0F0F0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

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
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

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
    _mobileController.dispose();
    _addressController.dispose();
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
        _mobileController.text = data['mobileNumber'] ?? '';
        _addressController.text = data['address'] ?? '';
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
      final String fullName = middleInitial.isEmpty
          ? '$firstName $lastName'
          : '$firstName ${middleInitial.replaceAll('.', '')}. $lastName';

      await user.updateDisplayName(fullName);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'middleInitial': middleInitial,
        'lastName': lastName,
        'fullName': fullName,
        'mobileNumber': _mobileController.text.replaceAll(
          RegExp(r'[^0-9]'),
          '',
        ),
        'address': _addressController.text.trim(),
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
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'First name is required'
                            : null,
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
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Last name is required'
                            : null,
                        decoration: _fieldDecoration(
                          'e.g. Zepp',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('MOBILE NUMBER'),
                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Mobile number is required';
                          }
                          final digitsOnly = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (!RegExp(r'^09\d{9}$').hasMatch(digitsOnly)) {
                            return 'Enter a valid mobile number (09XX XXX XXXX)';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          '09XX XXX XXXX',
                          Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('ADDRESS'),
                      TextFormField(
                        controller: _addressController,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Address is required'
                            : null,
                        decoration: _fieldDecoration(
                          'House No., Street, Barangay',
                          Icons.location_on_outlined,
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

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  CollectionReference<Map<String, dynamic>>? get _addressesRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('addresses');
  }

  Future<void> _addAddress() async {
    final labelController = TextEditingController();
    final addressController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                hintText: 'Label (e.g. Home, Office)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Full address'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: primaryGreen)),
          ),
        ],
      ),
    );

    if (saved != true) return;
    if (labelController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty) {
      return;
    }

    await _addressesRef?.add({
      'label': labelController.text.trim(),
      'address': addressController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteAddress(String docId) async {
    await _addressesRef?.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final ref = _addressesRef;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Saved Addresses'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryGreen,
        onPressed: _addAddress,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ref == null
          ? const Center(child: Text('Please log in to manage addresses.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: primaryGreen.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: primaryGreen,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No saved addresses',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to add a delivery address.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    90 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF0F0F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: primaryGreen.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: primaryGreen,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['label'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  data['address'] ?? '',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _deleteAddress(docs[index].id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  static const List<Map<String, String>> _sections = [
    {
      'title': '1. Account Registration & Eligibility',
      'body':
          'Business Verification: Almares 328 primarily serves wholesale and business '
          'customers. We reserve the right to require valid business documentation '
          '(e.g., business license, tax exemption certificate) to open a wholesale account.\n\n'
          'Accuracy of Information: You agree to provide current, complete, and accurate '
          'billing and contact information. You are responsible for all activities that '
          'occur under your account.\n\n'
          'Termination: We reserve the right to suspend or terminate your account at our '
          'sole discretion if we suspect fraudulent activity or a breach of these Terms.',
    },
    {
      'title': '2. Orders & Minimum Quantities',
      'body':
          'Minimum Order Requirements: Wholesale orders may be subject to Minimum Order '
          'Quantities (MOQs) or minimum spending thresholds, which will be communicated '
          'at the time of purchase.\n\n'
          'Order Acceptance: All orders are subject to stock availability and acceptance '
          'by Almares 328. We reserve the right to limit the quantities of any products '
          'or services that we offer.\n\n'
          'Substitutions: In the event a product is out of stock, we will not substitute '
          'items without your prior consent unless a pre-approved substitution agreement '
          'is in place.',
    },
    {
      'title': '3. Pricing & Payment Terms',
      'body':
          'Pricing: All prices are subject to change without notice due to market '
          'fluctuations in agricultural and grocery commodities. The price charged will '
          'be the price in effect at the time the order is placed.\n\n'
          'Payment Methods: We accept cash, major credit cards, bank transfers, and '
          'approved business checks.\n\n'
          'Credit Terms: For businesses with approved credit accounts, payment is due '
          'strictly within the agreed-upon window (e.g., Net 15, Net 30). Late payments '
          'may accrue a late fee of 1.5% per month on the outstanding balance.\n\n'
          'Taxes: Prices do not include applicable taxes. Customers claiming tax '
          'exemption must provide a valid certificate prior to purchase.',
    },
    {
      'title': '4. Delivery & Receiving Goods',
      'body':
          'Delivery Windows: Delivery times are estimates. Almares 328 is not liable for '
          'delays caused by severe weather, traffic, or unforeseen logistical constraints.\n\n'
          'Receiving & Inspection: The customer or an authorized representative must be '
          'present to receive and sign for deliveries. Title and risk of loss pass to you '
          'upon delivery.\n\n'
          'Cold Chain Compliance: For perishable goods, Almares 328 guarantees temperature '
          'control up to the point of delivery. Once delivered and signed for, the '
          'customer assumes full responsibility for proper storage.',
    },
    {
      'title': '5. Returns, Refunds & Claims',
      'body':
          'Due to the nature of wholesale groceries and health safety standards, our '
          'return policy is strict:\n\n'
          'Perishable Goods (Produce, Meat, Dairy): Claims for damaged, spoiled, or '
          'missing perishable items must be reported within 24 hours of delivery or '
          'pickup.\n\n'
          'Non-Perishable Goods: Claims for dry goods, canned items, or packaging defects '
          'must be reported within 3 business days.\n\n'
          'Return Process: To initiate a claim, you must provide photographic evidence of '
          'the damaged goods and the original invoice. Refunds will be issued as store '
          'credit or back to the original payment method, at our discretion.',
    },
    {
      'title': '6. Limitation of Liability',
      'body':
          'To the fullest extent permitted by law, Almares 328 Wholesale Grocery Store '
          'shall not be liable for any indirect, incidental, special, consequential, or '
          'punitive damages, including without limitation, loss of profits, loss of data, '
          'or business interruption arising out of your use of our products or services. '
          'Our maximum liability to you for any claim shall not exceed the amount you '
          'paid for the specific goods in question.',
    },
    {
      'title': '7. Force Majeure',
      'body':
          'Almares 328 shall not be held responsible for failure or delay in fulfilling '
          'our obligations under these Terms if such failure is caused by events beyond '
          'our reasonable control, including natural disasters, pandemics, strikes, '
          'supply chain disruptions, or government regulations.',
    },
    {
      'title': '8. Modifications to Terms',
      'body':
          'We reserve the right to update or modify these Terms & Conditions at any time. '
          'Changes will take effect immediately upon being posted on our website or '
          'posted in-store. Your continued use of our Services constitutes acceptance of '
          'the revised Terms.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Terms & Conditions'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Almares 328 Terms & Conditions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Last Updated: July 15, 2026',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Almares 328 Wholesale Grocery Store. These Terms & Conditions '
              '("Terms") govern your use of our physical store, website, and delivery '
              'services (collectively, the "Services"). By registering an account, '
              'placing an order, or shopping with us, you agree to be bound by these Terms.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            for (final section in _sections) ...[
              Text(
                section['title']!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                section['body']!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

Future<Set<String>> fetchBestSellingProductIds({int topN = 5}) async {
  final ordersSnapshot = await FirebaseFirestore.instance
      .collection('orders')
      .get();
  final Map<String, int> soldCounts = {};

  for (final doc in ordersSnapshot.docs) {
    final data = doc.data();
    final String? productId = data['productId'] as String?;
    if (productId == null) continue;
    final int amount = (data['amount'] as num?)?.toInt() ?? 0;
    soldCounts[productId] = (soldCounts[productId] ?? 0) + amount;
  }

  final sorted = soldCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sorted.take(topN).map((e) => e.key).toSet();
}

Future<void> seedProductCatalog() async {
  final products = FirebaseFirestore.instance.collection('products');

  await products.doc('lucky_me_pancit_canton').set({
    'name': 'Lucky Me Pancit Canton',
    'price': '₱17.00',
    'available': true,
    'flavors': [
      {'name': 'Red (Chili Mansi)', 'stock': 60, 'available': true},
      {'name': 'Orange (Sweet Style)', 'stock': 45, 'available': true},
      {'name': 'Yellow (Original)', 'stock': 80, 'available': true},
      {'name': 'Green (Kalamansi)', 'stock': 0, 'available': false},
    ],
  });

  await products.doc('555_sardines_tomato_sauce').set({
    'name': '555 Sardines in Tomato Sauce',
    'price': '₱32.00',
    'available': true,
    'stockCount': 180,
    'flavors': <Map<String, dynamic>>[],
  });
}

Future<Map<String, dynamic>> readStockDeduction(
  Transaction txn,
  DocumentReference<Map<String, dynamic>> productRef,
  String? flavorName,
  int amount,
) async {
  final snapshot = await txn.get(productRef);
  final data = snapshot.data();
  if (data == null) {
    throw Exception('This product is no longer available.');
  }

  final flavors =
      (data['flavors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

  if (flavors.isNotEmpty && flavorName != null) {
    final index = flavors.indexWhere((f) => f['name'] == flavorName);
    if (index == -1) {
      throw Exception('$flavorName is no longer available.');
    }
    final int currentStock = (flavors[index]['stock'] as num?)?.toInt() ?? 0;
    if (currentStock < amount) {
      throw Exception('Only $currentStock pcs of $flavorName left.');
    }
    final int newStock = currentStock - amount;
    final updatedFlavors = List<Map<String, dynamic>>.from(flavors);
    updatedFlavors[index] = {
      ...updatedFlavors[index],
      'stock': newStock,
      'available': newStock > 0,
    };
    return {'flavors': updatedFlavors};
  }

  final int currentStock = (data['stockCount'] as num?)?.toInt() ?? 0;
  if (currentStock < amount) {
    throw Exception('Only $currentStock pcs of ${data['name']} left.');
  }
  final int newStock = currentStock - amount;
  return {'stockCount': newStock, 'available': newStock > 0};
}

String cartItemId(String productName, String? flavorName) {
  final key = '$productName-${flavorName ?? 'default'}';
  return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

Future<void> addProductToCart({
  required Map<String, dynamic> product,
  required Map<String, dynamic>? flavor,
  required int amount,
  required double unitPrice,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception('Not signed in');
  }

  final String? productId = product['id'] as String?;
  final String productName = product['name'] as String? ?? '';
  final String? flavorName = flavor?['name'] as String?;
  final String? flavorImage = flavor?['imageUrl'] as String?;
  final String? imageUrl = (flavorImage != null && flavorImage.isNotEmpty)
      ? flavorImage
      : product['imageUrl'] as String?;
  final String docId = cartItemId(productName, flavorName);

  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('cart')
      .doc(docId);

  await ref.set({
    'productId': productId,
    'productName': productName,
    'imageUrl': imageUrl,
    'flavor': flavorName,
    'unitPrice': unitPrice,
    'amount': FieldValue.increment(amount),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

void showProductOptions(
  BuildContext context, {
  required Map<String, dynamic> product,
  required String mode,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Product options',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, anim1, anim2) {
      return ProductOptionsSheet(product: product, mode: mode);
    },
    transitionBuilder: (context, anim1, anim2, child) {
      final double blur = 8 * anim1.value;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

class ProductOptionsSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final String mode;

  const ProductOptionsSheet({
    super.key,
    required this.product,
    required this.mode,
  });

  @override
  State<ProductOptionsSheet> createState() => _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends State<ProductOptionsSheet> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  int _selectedFlavorIndex = 0;
  int _amount = 1;
  bool _isProcessing = false;

  List<Map<String, dynamic>> get _flavors =>
      (widget.product['flavors'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];

  Map<String, dynamic>? get _selectedFlavor =>
      _flavors.isNotEmpty ? _flavors[_selectedFlavorIndex] : null;

  bool get _isAvailable {
    if (_flavors.isNotEmpty) {
      return (_selectedFlavor?['available'] as bool?) ?? false;
    }
    return (widget.product['available'] as bool?) ?? true;
  }

  double get _unitPrice {
    final flavorPrice = _selectedFlavor?['price'] as String?;
    final priceString = (flavorPrice != null && flavorPrice.isNotEmpty)
        ? flavorPrice
        : (widget.product['price'] as String? ?? '₱0');
    final numeric = priceString.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(numeric) ?? 0;
  }

  void _incrementAmount() => setState(() => _amount++);

  void _decrementAmount() {
    if (_amount > 1) setState(() => _amount--);
  }

  Future<void> _handlePrimaryAction() async {
    if (_isProcessing) return;

    if (!_isAvailable) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Out of Stock'),
          content: const Text('This item is currently out of stock.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: primaryGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (widget.mode == 'order') {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderConfirmationScreen(
            product: widget.product,
            flavor: _selectedFlavor,
            amount: _amount,
            unitPrice: _unitPrice,
          ),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await addProductToCart(
        product: widget.product,
        flavor: _selectedFlavor,
        amount: _amount,
        unitPrice: _unitPrice,
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Added $_amount x ${widget.product['name']} to your cart.',
          ),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 130),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Could not add to cart. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.product['name'] as String? ?? '';
    final String price = '₱${_unitPrice.toStringAsFixed(2)}';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ProductImage(
                    imageUrl:
                        (_selectedFlavor?['imageUrl'] as String?) ??
                        widget.product['imageUrl'] as String?,
                    iconSize: 36,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryGreen,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (_isAvailable ? primaryGreen : Colors.redAccent)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isAvailable ? 'Available' : 'Out of Stock',
                        style: TextStyle(
                          color: _isAvailable ? primaryGreen : Colors.redAccent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                if (_flavors.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'FLAVOR',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: List.generate(_flavors.length, (index) {
                      final flavor = _flavors[index];
                      final bool selected = index == _selectedFlavorIndex;
                      final bool available =
                          (flavor['available'] as bool?) ?? false;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: selected
                              ? primaryGreen.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: available
                                ? () => setState(
                                    () => _selectedFlavorIndex = index,
                                  )
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? primaryGreen
                                      : const Color(0xFFF0F0F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: available
                                        ? primaryGreen
                                        : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 8),
                                  if ((flavor['imageUrl'] as String?)
                                          ?.isNotEmpty ??
                                      false) ...[
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: ProductImage(
                                        imageUrl: flavor['imageUrl'] as String?,
                                        iconSize: 12,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      flavor['name'] as String? ?? '',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: available
                                            ? Colors.black87
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    available
                                        ? '${(flavor['price'] as String?) ?? ''} '
                                              '• ${flavor['stock']} pcs'
                                        : 'Out of stock',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: available
                                          ? Colors.grey.shade600
                                          : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],

                const SizedBox(height: 18),
                const Text(
                  'AMOUNT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _AmountButton(icon: Icons.remove, onTap: _decrementAmount),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_amount',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    _AmountButton(icon: Icons.add, onTap: _incrementAmount),
                  ],
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isAvailable && !_isProcessing)
                        ? _handlePrimaryAction
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 2,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            widget.mode == 'order'
                                ? 'Proceed to Order'
                                : 'Add to Cart',
                            style: const TextStyle(
                              fontSize: 15,
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

class _AmountButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AmountButton({required this.icon, required this.onTap});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primaryGreen.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: primaryGreen, size: 20),
        ),
      ),
    );
  }
}

Future<String?> pickDeliveryAddress(
  BuildContext context,
  String currentAddress,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();
  final String profileAddress = (userDoc.data()?['address'] as String?) ?? '';

  final addressesSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('addresses')
      .orderBy('createdAt', descending: true)
      .get();

  if (!context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Choose Delivery Address',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (profileAddress.trim().isNotEmpty)
                  ListTile(
                    leading: Icon(
                      currentAddress == profileAddress
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: const Color(0xFF2E6B3E),
                    ),
                    title: const Text('Profile Address'),
                    subtitle: Text(profileAddress),
                    onTap: () => Navigator.pop(context, profileAddress),
                  ),
                if (addressesSnapshot.docs.isNotEmpty) const Divider(height: 1),
                ...addressesSnapshot.docs.map((doc) {
                  final data = doc.data();
                  final String label = data['label'] as String? ?? 'Address';
                  final String address = data['address'] as String? ?? '';
                  final bool isSelected = currentAddress == address;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: const Color(0xFF2E6B3E),
                    ),
                    title: Text(label),
                    subtitle: Text(address),
                    onTap: () => Navigator.pop(context, address),
                  );
                }),
                if (profileAddress.trim().isEmpty &&
                    addressesSnapshot.docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No saved addresses yet. Add one from Profile > Saved Addresses.',
                      style: TextStyle(color: Colors.grey, fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class OrderConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? flavor;
  final int amount;
  final double unitPrice;

  const OrderConfirmationScreen({
    super.key,
    required this.product,
    required this.flavor,
    required this.amount,
    required this.unitPrice,
  });

  @override
  State<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isLoading = true;
  bool _isConfirming = false;

  String _customerName = '';
  String _customerAddress = '';
  late final DateTime _orderTime;
  late final DateTime _estimatedDelivery;
  late final String _orderNumber;

  @override
  void initState() {
    super.initState();
    _orderTime = DateTime.now();
    _estimatedDelivery = _orderTime.add(const Duration(days: 3));
    _orderNumber = FirebaseFirestore.instance.collection('orders').doc().id;
    _loadCustomerInfo();
  }

  Future<void> _loadCustomerInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    _customerName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Guest');

    try {
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _customerAddress = (doc.data()?['address'] as String?) ?? '';
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$minute $period';
  }

  Future<void> _confirmOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_customerAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please add a delivery address in your profile before ordering.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    final String? productId = widget.product['id'] as String?;

    setState(() => _isConfirming = true);

    final double total = widget.unitPrice * widget.amount;
    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(_orderNumber);

    try {
      if (productId != null) {
        final productRef = FirebaseFirestore.instance
            .collection('products')
            .doc(productId);

        final String? itemImage =
            (widget.flavor != null && widget.flavor!['imageUrl'] != null)
            ? widget.flavor!['imageUrl'] as String?
            : widget.product['imageUrl'] as String?;

        await FirebaseFirestore.instance.runTransaction((txn) async {
          final stockUpdate = await readStockDeduction(
            txn,
            productRef,
            widget.flavor?['name'] as String?,
            widget.amount,
          );
          txn.update(productRef, stockUpdate);
          txn.set(orderRef, {
            'userId': user.uid,
            'customerName': _customerName,
            'customerAddress': _customerAddress,
            'items': [
              {
                'productId': productId,
                'productName': widget.product['name'],
                'imageUrl': itemImage,
                'flavor': widget.flavor?['name'],
                'amount': widget.amount,
                'unitPrice': widget.unitPrice,
                'subtotal': total,
              },
            ],
            'itemCount': 1,
            'total': total,
            'status': 'pending',
            'estimatedDelivery': Timestamp.fromDate(_estimatedDelivery),
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
      } else {
        final String? itemImage =
            (widget.flavor != null && widget.flavor!['imageUrl'] != null)
            ? widget.flavor!['imageUrl'] as String?
            : widget.product['imageUrl'] as String?;

        await orderRef.set({
          'userId': user.uid,
          'customerName': _customerName,
          'customerAddress': _customerAddress,
          'items': [
            {
              'productId': null,
              'productName': widget.product['name'],
              'imageUrl': itemImage,
              'flavor': widget.flavor?['name'],
              'amount': widget.amount,
              'unitPrice': widget.unitPrice,
              'subtotal': total,
            },
          ],
          'itemCount': 1,
          'total': total,
          'status': 'pending',
          'estimatedDelivery': Timestamp.fromDate(_estimatedDelivery),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await addEmployeeOrderNotification(
        message:
            '$_customerName placed a new order: '
            '${widget.product['name']}.',
        orderId: _orderNumber,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Order placed successfully!'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Widget _detailRow(String label, String value, {bool noPadding = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double total = widget.unitPrice * widget.amount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Confirm Order'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.product['name'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                                if (widget.flavor != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Flavor: ${widget.flavor!['name']}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Qty: ${widget.amount}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _detailRow('Customer Name', _customerName),
                    GestureDetector(
                      onTap: () async {
                        final picked = await pickDeliveryAddress(
                          context,
                          _customerAddress,
                        );
                        if (picked != null) {
                          setState(() => _customerAddress = picked);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _detailRow(
                                'Customer Address',
                                _customerAddress,
                                noPadding: true,
                              ),
                            ),
                            const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: primaryGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _detailRow(
                      'Estimated Delivery',
                      _formatDate(_estimatedDelivery),
                    ),
                    _detailRow(
                      'Order Number',
                      '#${_orderNumber.substring(0, 8).toUpperCase()}',
                    ),
                    _detailRow('Time of Order', _formatDate(_orderTime)),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isConfirming ? null : _confirmOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                          elevation: 3,
                        ),
                        child: _isConfirming
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Confirm Order',
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
    );
  }
}

class EmployeeReportsScreen extends StatefulWidget {
  const EmployeeReportsScreen({super.key});

  @override
  State<EmployeeReportsScreen> createState() => _EmployeeReportsScreenState();
}

class _EmployeeReportsScreenState extends State<EmployeeReportsScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  DateTime? _selectedMonth;
  bool _isExporting = false;

  String get _periodLabel {
    if (_selectedMonth == null) return 'All Time';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[_selectedMonth!.month - 1]} ${_selectedMonth!.year}';
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final List<DateTime> months = List.generate(
      12,
      (i) => DateTime(now.year, now.month - i),
    );

    final selected = await showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select Period',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.all_inclusive, color: primaryGreen),
                  title: const Text('All Time'),
                  trailing: _selectedMonth == null
                      ? const Icon(Icons.check, color: primaryGreen)
                      : null,
                  onTap: () => Navigator.pop(context, null),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: months.length,
                    itemBuilder: (context, index) {
                      final m = months[index];
                      const monthNames = [
                        'Jan',
                        'Feb',
                        'Mar',
                        'Apr',
                        'May',
                        'Jun',
                        'Jul',
                        'Aug',
                        'Sep',
                        'Oct',
                        'Nov',
                        'Dec',
                      ];
                      final bool isSelected =
                          _selectedMonth != null &&
                          _selectedMonth!.year == m.year &&
                          _selectedMonth!.month == m.month;
                      return ListTile(
                        title: Text('${monthNames[m.month - 1]} ${m.year}'),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: primaryGreen)
                            : null,
                        onTap: () => Navigator.pop(context, m),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != _selectedMonth) {
      setState(() => _selectedMonth = selected);
    }
  }

  bool _inSelectedPeriod(Timestamp? createdAt) {
    if (_selectedMonth == null) return true;
    if (createdAt == null) return false;
    final d = createdAt.toDate();
    return d.year == _selectedMonth!.year && d.month == _selectedMonth!.month;
  }

  Map<String, dynamic> _computeMetrics(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
  ) {
    int totalOrders = 0;
    int totalDelivered = 0;
    int totalPaidItems = 0;
    double totalSales = 0;
    int pending = 0;
    int cancelledOrRejected = 0;

    for (final doc in orderDocs) {
      final data = doc.data();
      if (!_inSelectedPeriod(data['createdAt'] as Timestamp?)) continue;

      totalOrders++;
      final String status = (data['status'] ?? '').toString().toLowerCase();
      final bool isPaid = (data['isPaid'] as bool?) ?? false;

      if (status == 'delivered') {
        totalDelivered++;
        if (isPaid) {
          totalSales += (data['total'] as num?)?.toDouble() ?? 0;
          for (final item in getOrderItems(data)) {
            totalPaidItems += (item['amount'] as num?)?.toInt() ?? 0;
          }
        }
      } else if (status == 'pending') {
        pending++;
      } else if (status == 'cancelled' ||
          status == 'rejected' ||
          status == 'undelivered') {
        cancelledOrRejected++;
      }
    }

    return {
      'totalOrders': totalOrders,
      'totalDelivered': totalDelivered,
      'totalPaidItems': totalPaidItems,
      'totalSales': totalSales,
      'pending': pending,
      'cancelledOrRejected': cancelledOrRejected,
    };
  }

  Future<void> _exportPdf(
    Map<String, dynamic> metrics,
    int criticalCount,
    int lowCount,
    int outOfStockCount,
  ) async {
    setState(() => _isExporting = true);
    try {
      final pdf = pw.Document();

      pw.ImageProvider? logoImage;
      try {
        final logoBytes = await rootBundle.load('assets/images/logo.png');
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {
        logoImage = null;
      }

      final primaryPdfColor = PdfColor.fromInt(0xFF2E6B3E);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null) ...[
                      pw.Container(
                        width: 48,
                        height: 48,
                        child: pw.Image(logoImage),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Almares 328',
                            style: pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryPdfColor,
                            ),
                          ),
                          pw.Text(
                            'Sales & Inventory Report',
                            style: const pw.TextStyle(
                              fontSize: 11,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(color: primaryPdfColor, thickness: 1.2),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Period: $_periodLabel',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.Text(
                      'Generated: ${DateTime.now().toString().split('.').first}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),

                _sectionHeader('ORDER SUMMARY', primaryPdfColor),
                pw.SizedBox(height: 8),
                _pdfTable([
                  ['Total Orders', '${metrics['totalOrders']}'],
                  ['Total Delivered Orders', '${metrics['totalDelivered']}'],
                  ['Total Paid Items', '${metrics['totalPaidItems']}'],
                  [
                    'Total Sales',
                    'PHP ${(metrics['totalSales'] as double).toStringAsFixed(2)}',
                  ],
                  ['Pending Orders', '${metrics['pending']}'],
                  [
                    'Cancelled / Rejected Orders',
                    '${metrics['cancelledOrRejected']}',
                  ],
                ], primaryPdfColor),

                pw.SizedBox(height: 24),
                _sectionHeader('INVENTORY SNAPSHOT (CURRENT)', primaryPdfColor),
                pw.SizedBox(height: 8),
                _pdfTable([
                  ['Critically Low Stock', '$criticalCount'],
                  ['Low Stock', '$lowCount'],
                  ['Out of Stock', '$outOfStockCount'],
                ], primaryPdfColor),

                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.Center(
                  child: pw.Text(
                    'Almares 328 - Wholesale Grocery & Sari-Sari Store',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey500,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'almares328_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  pw.Widget _sectionHeader(String title, PdfColor color) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: color,
        letterSpacing: 0.5,
      ),
    );
  }

  pw.Widget _pdfTable(List<List<String>> rows, PdfColor accentColor) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: pw.Text(row[0], style: const pw.TextStyle(fontSize: 11)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: pw.Text(
                row[1],
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Reports'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, orderSnapshot) {
          if (!orderSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final metrics = _computeMetrics(orderSnapshot.data!.docs);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .snapshots(),
            builder: (context, productSnapshot) {
              int criticalCount = 0;
              int lowCount = 0;
              int outOfStockCount = 0;

              for (final doc in productSnapshot.data?.docs ?? []) {
                final stock = extractTotalStock(doc.data());
                if (stock <= 0) {
                  outOfStockCount++;
                } else {
                  final level = getStockLevel(stock);
                  if (level == StockLevel.critical) {
                    criticalCount++;
                  } else if (level == StockLevel.low) {
                    lowCount++;
                  }
                }
              }

              return SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    20 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        onTap: _pickMonth,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: primaryGreen.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                color: primaryGreen,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _periodLabel,
                                  style: const TextStyle(
                                    color: primaryGreen,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: primaryGreen,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'ORDER SUMMARY',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Total Orders',
                              value: '${metrics['totalOrders']}',
                              icon: Icons.receipt_long_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              label: 'Delivered',
                              value: '${metrics['totalDelivered']}',
                              icon: Icons.local_shipping_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Paid Items Sold',
                              value: '${metrics['totalPaidItems']}',
                              icon: Icons.shopping_bag_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              label: 'Total Sales',
                              value:
                                  '\u20b1${(metrics['totalSales'] as double).toStringAsFixed(2)}',
                              icon: Icons.payments_outlined,
                              highlight: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Pending',
                              value: '${metrics['pending']}',
                              icon: Icons.hourglass_empty,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              label: 'Cancelled/Rejected',
                              value: '${metrics['cancelledOrRejected']}',
                              icon: Icons.cancel_outlined,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'INVENTORY SNAPSHOT (CURRENT)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Critically Low',
                              value: '$criticalCount',
                              icon: Icons.error_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              label: 'Low Stock',
                              value: '$lowCount',
                              icon: Icons.warning_amber_outlined,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              label: 'Out of Stock',
                              value: '$outOfStockCount',
                              icon: Icons.block,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting
                              ? null
                              : () => _exportPdf(
                                  metrics,
                                  criticalCount,
                                  lowCount,
                                  outOfStockCount,
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  color: Colors.white,
                                ),
                          label: Text(
                            _isExporting ? 'Exporting...' : 'Export to PDF',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final bool highlight;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.highlight = false,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final Color accent = color ?? primaryGreen;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? primaryGreen.withValues(alpha: 0.08)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: highlight
            ? Border.all(color: primaryGreen.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class OrderItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const OrderItemCard({super.key, required this.item});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final String name = item['productName'] as String? ?? '';
    final String? flavor = item['flavor'] as String?;
    final int amount = (item['amount'] as num?)?.toInt() ?? 0;
    final double unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
    final double subtotal =
        (item['subtotal'] as num?)?.toDouble() ?? (unitPrice * amount);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ProductImage(
              imageUrl: item['imageUrl'] as String?,
              iconSize: 24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${unitPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (flavor != null && flavor.isNotEmpty) ? flavor : ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    Text(
                      'x$amount',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₱${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OrderItemsListScreen extends StatelessWidget {
  final String orderId;
  final List<Map<String, dynamic>> items;
  final double total;

  const OrderItemsListScreen({
    super.key,
    required this.orderId,
    required this.items,
    required this.total,
  });

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: Text(
          'Order #${orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase()}',
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${items.length} ITEMS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            ...items.map((item) => OrderItemCard(item: item)),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ORDER TOTAL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class CartOrderConfirmationScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String initialAddress;

  const CartOrderConfirmationScreen({
    super.key,
    required this.docs,
    required this.initialAddress,
  });

  @override
  State<CartOrderConfirmationScreen> createState() =>
      _CartOrderConfirmationScreenState();
}

class _CartOrderConfirmationScreenState
    extends State<CartOrderConfirmationScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  bool _isConfirming = false;
  String _customerName = '';
  late String _customerAddress;
  late final DateTime _estimatedDelivery;

  @override
  void initState() {
    super.initState();
    _customerAddress = widget.initialAddress;
    _estimatedDelivery = DateTime.now().add(const Duration(days: 3));
    final user = FirebaseAuth.instance.currentUser;
    _customerName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Guest');
  }

  double get _total {
    double total = 0;
    for (final doc in widget.docs) {
      final data = doc.data();
      final double unitPrice = (data['unitPrice'] as num?)?.toDouble() ?? 0;
      final int amount = (data['amount'] as num?)?.toInt() ?? 0;
      total += unitPrice * amount;
    }
    return total;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$minute $period';
  }

  Future<void> _changeAddress() async {
    final picked = await pickDeliveryAddress(context, _customerAddress);
    if (picked != null) setState(() => _customerAddress = picked);
  }

  Future<void> _confirmOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.docs.isEmpty) return;

    if (_customerAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please choose a delivery address before confirming.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isConfirming = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final ordersCollection = FirebaseFirestore.instance.collection('orders');
      final productsCollection = FirebaseFirestore.instance.collection(
        'products',
      );
      final orderRef = ordersCollection.doc();

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final Map<String, Map<String, dynamic>> stockUpdates = {};

        for (final doc in widget.docs) {
          final data = doc.data();
          final String? productId = data['productId'] as String?;
          if (productId == null) continue;

          final String? flavorName = data['flavor'] as String?;
          final int amount = (data['amount'] as num?)?.toInt() ?? 0;
          final productRef = productsCollection.doc(productId);

          stockUpdates[productId] = await readStockDeduction(
            txn,
            productRef,
            flavorName,
            amount,
          );
        }

        stockUpdates.forEach((productId, update) {
          txn.update(productsCollection.doc(productId), update);
        });

        final List<Map<String, dynamic>> orderItems = [];
        double orderTotal = 0;

        for (final doc in widget.docs) {
          final data = doc.data();
          final double unitPrice = (data['unitPrice'] as num?)?.toDouble() ?? 0;
          final int amount = (data['amount'] as num?)?.toInt() ?? 0;
          final double subtotal = unitPrice * amount;
          orderTotal += subtotal;

          orderItems.add({
            'productId': data['productId'],
            'productName': data['productName'],
            'imageUrl': data['imageUrl'],
            'flavor': data['flavor'],
            'amount': amount,
            'unitPrice': unitPrice,
            'subtotal': subtotal,
          });

          txn.delete(doc.reference);
        }

        txn.set(orderRef, {
          'userId': user.uid,
          'customerName': _customerName,
          'customerAddress': _customerAddress,
          'items': orderItems,
          'itemCount': orderItems.length,
          'total': orderTotal,
          'status': 'pending',
          'estimatedDelivery': Timestamp.fromDate(_estimatedDelivery),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      await addEmployeeOrderNotification(
        message:
            '$_customerName placed a new order '
            '(${widget.docs.length} item${widget.docs.length == 1 ? '' : 's'}).',
        orderId: orderRef.id,
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Order placed successfully!'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConfirming = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Confirm Order'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ITEMS (${widget.docs.length})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.docs.map((doc) {
                final data = doc.data();
                return OrderItemCard(item: data);
              }),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ORDER TOTAL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '₱${_total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'CUSTOMER NAME',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _customerName,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: _changeAddress,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DELIVERY ADDRESS',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _customerAddress.trim().isEmpty
                                ? 'Tap to add an address'
                                : _customerAddress,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: _customerAddress.trim().isEmpty
                                  ? Colors.redAccent
                                  : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'ESTIMATED DELIVERY',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(_estimatedDelivery),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isConfirming ? null : _confirmOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _isConfirming
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Confirm Order',
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
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final bool _isCheckingOut = false;
  final Set<String> _selectedIds = {};
  String _selectedAddress = '';
  bool _addressLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultAddress();
  }

  Future<void> _loadDefaultAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (mounted) {
      setState(() {
        _selectedAddress = (doc.data()?['address'] as String?) ?? '';
        _addressLoaded = true;
      });
    }
  }

  Future<void> _changeAddress() async {
    final picked = await pickDeliveryAddress(context, _selectedAddress);
    if (picked != null) setState(() => _selectedAddress = picked);
  }

  void _toggleSelected(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  void _selectAll(List<String> allIds) {
    setState(() {
      if (_selectedIds.length == allIds.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  CollectionReference<Map<String, dynamic>>? get _cartRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cart');
  }

  Future<void> _updateQuantity(String docId, int newAmount) async {
    if (newAmount <= 0) {
      await _cartRef?.doc(docId).delete();
      return;
    }
    await _cartRef?.doc(docId).update({'amount': newAmount});
  }

  Future<void> _removeItem(String docId) async {
    await _cartRef?.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final ref = _cartRef;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Cart'),
      ),
      body: ref == null
          ? const Center(child: Text('Please log in to view your cart.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref.orderBy('updatedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: primaryGreen.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              color: primaryGreen,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Your cart is empty',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Items you add to your cart will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (_selectedIds.isEmpty && docs.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedIds.isEmpty) {
                      setState(
                        () => _selectedIds.addAll(docs.map((d) => d.id)),
                      );
                    }
                  });
                }

                final selectedDocs = docs
                    .where((d) => _selectedIds.contains(d.id))
                    .toList();

                double total = 0;
                for (final doc in selectedDocs) {
                  final data = doc.data();
                  final double unitPrice =
                      (data['unitPrice'] as num?)?.toDouble() ?? 0;
                  final int amount = (data['amount'] as num?)?.toInt() ?? 0;
                  total += unitPrice * amount;
                }

                final bool allSelected =
                    docs.isNotEmpty && _selectedIds.length == docs.length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: GestureDetector(
                        onTap: () => _selectAll(docs.map((d) => d.id).toList()),
                        child: Row(
                          children: [
                            Icon(
                              allSelected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: primaryGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              allSelected ? 'Deselect All' : 'Select All',
                              style: const TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          20 + MediaQuery.of(context).padding.bottom,
                        ),
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final String productName =
                              data['productName'] as String? ?? '';
                          final String? flavor = data['flavor'] as String?;
                          final double unitPrice =
                              (data['unitPrice'] as num?)?.toDouble() ?? 0;
                          final int amount =
                              (data['amount'] as num?)?.toInt() ?? 0;
                          final bool isSelected = _selectedIds.contains(doc.id);

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryGreen.withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? primaryGreen
                                    : const Color(0xFFF0F0F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _toggleSelected(doc.id),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    color: primaryGreen,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: ProductImage(
                                    imageUrl: data['imageUrl'] as String?,
                                    iconSize: 22,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        productName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      if (flavor != null &&
                                          flavor.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          flavor,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '₱${unitPrice.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: primaryGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        _CartQtyButton(
                                          icon: Icons.remove,
                                          onTap: () => _updateQuantity(
                                            doc.id,
                                            amount - 1,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 28,
                                          child: Text(
                                            '$amount',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        _CartQtyButton(
                                          icon: Icons.add,
                                          onTap: () => _updateQuantity(
                                            doc.id,
                                            amount + 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    TextButton(
                                      onPressed: () => _removeItem(doc.id),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 0),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Remove',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              onTap: _addressLoaded ? _changeAddress : null,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    color: primaryGreen,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: !_addressLoaded
                                        ? Text(
                                            'Loading address...',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: Colors.grey.shade500,
                                            ),
                                          )
                                        : Text(
                                            _selectedAddress.trim().isEmpty
                                                ? 'Add a delivery address'
                                                : _selectedAddress,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color:
                                                  _selectedAddress
                                                      .trim()
                                                      .isEmpty
                                                  ? Colors.redAccent
                                                  : Colors.black87,
                                            ),
                                          ),
                                  ),
                                  if (_addressLoaded)
                                    const Text(
                                      'Change',
                                      style: TextStyle(
                                        color: primaryGreen,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total (${selectedDocs.length} item${selectedDocs.length == 1 ? '' : 's'})',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  '₱${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed:
                                    (_isCheckingOut ||
                                        selectedDocs.isEmpty ||
                                        _selectedAddress.trim().isEmpty)
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                CartOrderConfirmationScreen(
                                                  docs: selectedDocs,
                                                  initialAddress:
                                                      _selectedAddress,
                                                ),
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryGreen,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  elevation: 3,
                                ),
                                child: _isCheckingOut
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'Proceed to Checkout',
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
                  ],
                );
              },
            ),
    );
  }
}

class _CartQtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CartQtyButton({required this.icon, required this.onTap});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primaryGreen.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, color: primaryGreen, size: 15),
        ),
      ),
    );
  }
}
