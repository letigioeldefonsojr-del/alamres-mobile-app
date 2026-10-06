import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'services/onesignal_service.dart';
import 'services/suspension_watcher.dart';
import 'screens/splash_screen.dart';

// Lets SuspensionWatcher force navigation back to the login screen from
// anywhere in the app - not just from whatever screen happens to be
// showing when it detects a suspension.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
    // Same reasoning as at login: a slow/unreachable OneSignal call must
    // never block the app from starting for an already-signed-in customer.
    unawaited(
      OneSignalService.instance
          .login(FirebaseAuth.instance.currentUser!.uid)
          .timeout(const Duration(seconds: 5), onTimeout: () {}),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Almares 328 Login',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        primaryColor: const Color(0xFF2E6B3E),
        fontFamily: 'BricolageGrotesque',
      ),
      // `builder` wraps whatever route is currently showing without
      // itself being torn down on navigation, which is exactly what a
      // watcher that has to survive across every screen needs.
      builder: (context, child) => SuspensionWatcher(
        navigatorKey: navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const SplashScreen(),
    );
  }
}
