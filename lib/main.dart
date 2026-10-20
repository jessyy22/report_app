import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/commuters/navigation_bar.dart';
import 'screens/drivers/driver_dashboard.dart';
import 'screens/splash_screen.dart';
import 'screens/login.dart';
import 'theme/app_theme.dart';
import 'screens/common/terms_privacy_screen.dart';
import 'screens/reset_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://haryaqpwigdqthiulgwu.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhhcnlhcXB3aWdkcXRoaXVsZ3d1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4NzY2NDAsImV4cCI6MjA5MTQ1MjY0MH0.iW3Tujg1Q81Fsepj6LgBef7f1s0cMhJcSoEmjpWSKRk',
  );

  runApp(const RTODAPassengerApp());
}

class RTODAPassengerApp extends StatefulWidget {
  const RTODAPassengerApp({super.key});

  @override
  State<RTODAPassengerApp> createState() => _RTODAPassengerAppState();
}

class _RTODAPassengerAppState extends State<RTODAPassengerApp> {
  final AppLinks _appLinks = AppLinks();
  final _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initAuthListener();
    _initDeepLinks();
  }

  // ── Auth listener — fires on password recovery ───────────
  void _initAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      debugPrint('AUTH EVENT: ${data.event}');

      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navigateTo('/reset-password');
      }
    });
  }

  // ── Deep link init ────────────────────────────────────────
  Future<void> _initDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }

      _linkSubscription = _appLinks.uriLinkStream.listen(
        _handleDeepLink,
        onError: (error) {
          debugPrint('Deep link error: $error');
        },
      );
    } catch (e) {
      debugPrint('Deep link initialization error: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('RTODA DEEP LINK: $uri');

    if (uri.scheme != 'rtoda') return;

    switch (uri.host) {
      case 'login-callback':
        _navigateTo('/login');
        break;
      case 'reset-password':
        // Handled by AuthChangeEvent.passwordRecovery above.
        // No navigation here — prevents double-navigation.
        debugPrint('Reset deep link received — waiting for auth event.');
        break;
      default:
        debugPrint('Unknown deep link host: ${uri.host}');
    }
  }

  // ── Navigator helper ──────────────────────────────────────
  void _navigateTo(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navigatorKey.currentState;
      if (nav == null) return;

      final current = ModalRoute.of(
        _navigatorKey.currentContext ?? nav.context,
      )?.settings.name;

      if (current == route) return; // avoid duplicate push

      nav.pushNamedAndRemoveUntil(route, (_) => false);
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'RTODA Report App',
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/terms': (_) => const TermsPrivacyScreen(),
        '/login': (_) => const LoginPage(),
        '/reset-password': (_) => const ResetPasswordScreen(),
        '/driver_dashboard': (_) => const DriverDashboard(),
        '/navigation_bar': (_) => const NavigationBarApp(),
      },
    );
  }
}
