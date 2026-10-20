import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'account_status_screen.dart';
import 'email_verification_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  SupabaseClient get client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  // ============================================================
  // MAIN FLOW
  // ============================================================
  Future<void> _checkAuth() async {
    // Short brand delay — keep under 500ms.
    await Future.delayed(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    final agreedToTerms = prefs.getBool('rtoda_terms_agreed') ?? false;

    if (!agreedToTerms) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/terms');
      return;
    }

    final session = client.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      await _validateSession(session.user).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      debugPrint('SPLASH: session validation timed out');
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e, stackTrace) {
      debugPrint('SPLASH AUTH ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _validateSession(User user) async {
    final roleData = await client
        .from('user_roles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    if (!mounted) return;

    if (roleData == null) {
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final role = (roleData['role'] ?? '').toString().trim().toLowerCase();
    final isNewAuthFlow = user.userMetadata?['rtoda_auth_v2'] == true;

    // ── Email verification gate ─────────────────────────────
    if (isNewAuthFlow && user.emailConfirmedAt == null) {
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              EmailVerificationScreen(email: user.email ?? 'your email'),
        ),
      );
      return;
    }

    // ── Driver route ────────────────────────────────────────
    if (role == 'driver') {
      await _routeDriver(user);
      return;
    }

    // ── Commuter route ──────────────────────────────────────
    if (role == 'commuter') {
      await _routeCommuter(user, isNewAuthFlow);
      return;
    }

    // ── Unknown role ────────────────────────────────────────
    await _safeSignOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _routeDriver(User user) async {
    final driverData = await client
        .from('driver_profiles')
        .select('is_active, verification_status')
        .eq('id', user.id)
        .maybeSingle();

    if (!mounted) return;

    if (driverData == null) {
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AccountStatusScreen(status: 'pending'),
        ),
      );
      return;
    }

    final status = _driverStatus(driverData);
    final isActive = driverData['is_active'] == true;

    if (status != 'approved') {
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AccountStatusScreen(status: status)),
      );
      return;
    }

    if (!isActive) {
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AccountStatusScreen(status: 'inactive'),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/driver_dashboard');
  }

  Future<void> _routeCommuter(User user, bool isNewAuthFlow) async {
    final profile = await client
        .from('commuter_profiles')
        .select('id, is_verified')
        .eq('id', user.id)
        .maybeSingle();

    if (!mounted) return;

    if (profile == null) {
      // Profile missing — signed up but never completed.
      await _safeSignOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    if (isNewAuthFlow && profile['is_verified'] != true) {
      try {
        await client
            .from('commuter_profiles')
            .update({'is_verified': true})
            .eq('id', user.id);
      } catch (e) {
        debugPrint('Commuter verification update failed: $e');
      }
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/navigation_bar');
  }

  String _driverStatus(Map<String, dynamic>? data) {
    if (data == null) return 'pending';

    final status = data['verification_status']?.toString().trim().toLowerCase();

    if (status == 'approved' ||
        status == 'pending' ||
        status == 'rejected' ||
        status == 'suspended') {
      return status!;
    }

    if (data['is_active'] == true) return 'approved';
    return 'pending';
  }

  Future<void> _safeSignOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      debugPrint('SPLASH SIGN OUT ERROR: $e');
    }
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 130,
                width: 130,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(18),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  fit: BoxFit.contain,
                  semanticLabel: 'RTODA Vigan logo',
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.local_police,
                    size: 80,
                    color: AppColors.green,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'RTODA VIGAN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Report • Monitor • Protect',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 48),
              Semantics(
                label: 'Loading your account…',
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
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
