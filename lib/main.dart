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
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initAuthListener();
    _initDeepLinks();
  }

  void _initAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/reset-password', (route) => false);
          });
        }
      },
      onError: (error) {
        debugPrint('Auth state error: $error');
      },
    );
  }

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (uri.scheme == 'rtoda' && uri.host == 'login-callback') {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
        return;
      }

      if (uri.scheme == 'rtoda' && uri.host == 'reset-password') {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/reset-password', (route) => false);
        return;
      }
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
      debugShowCheckedModeBanner: false,
      title: 'RTODA Report App',
      theme: AppTheme.light,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/driver_dashboard': (context) => const DriverDashboard(),
        '/navigation_bar': (context) => const NavigationBarApp(),
      },
    );
  }
}
