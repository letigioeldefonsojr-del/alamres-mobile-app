import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'services/onesignal_service.dart';
import 'services/engagement_reminder_service.dart';
import 'services/suspension_watcher.dart';
import 'screens/splash_screen.dart';
import 'core/product_view_preference.dart';
import 'services/product_repository.dart';

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

  // Loads the customer's saved list/grid view choice before the first
  // frame, so every product grid screen already reflects it instead of
  // flashing the grid2 default first - see product_view_preference.dart.
  await ProductViewPreference.ensureLoaded();

  // Loads whatever product catalog is cached on disk (near-instant) and
  // kicks off a real refresh in the background - see product_repository.dart
  // for why the catalog needs its own shared owner now that Supabase (the
  // product backend, when kUseSupabaseProducts is on) has no realtime
  // listener the way Firestore did.
  unawaited(ProductRepository.instance.ensureStarted());

  if (!kIsWeb) {
    await OneSignalService.instance.init(
      'c3b735fb-99e4-49be-8f63-e8606b95d918',
    );
    await OneSignal.Notifications.requestPermission(true);
    // Tapping a push (order status update, etc.) should take the customer
    // straight to their Orders tab - see OneSignalService for the details.
    OneSignalService.instance.setupNotificationClickHandling(navigatorKey);
    // Purely local "Shop Reminders" - separate from OneSignal above, see
    // EngagementReminderService for why. Just sets the plugin up here;
    // whether anything actually gets scheduled depends on the customer's
    // own toggle (checked in HomeScreen/NotificationsScreen).
    await EngagementReminderService.instance.init();
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

// StatefulWidget (rather than the StatelessWidget this used to be) purely
// so WidgetsBindingObserver has somewhere to live - its only job is
// telling ProductRepository when the app comes back to the foreground, so
// a catalog that went stale while the app was backgrounded refreshes right
// away instead of waiting for the next periodic tick.
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ProductRepository.instance.onAppResumed();
    }
  }

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
