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

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
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

    if (uri.scheme == 'rtoda' && uri.host == 'login-callback') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      });
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
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
        '/driver_dashboard': (context) => const DriverDashboard(),
        '/navigation_bar': (context) => const NavigationBarApp(),
      },
    );
  }
}
