import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_status_screen.dart';
import 'login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 1));

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    if (!mounted) return;

    if (session == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      final user = session.user;

      final roleData = await client
          .from('user_roles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (roleData == null) {
        await client.auth.signOut();

        if (!mounted) return;

        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final role = (roleData['role'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final isNewAuthFlow =
          user.userMetadata?['rtoda_auth_v2'] == true;

      if (isNewAuthFlow && user.emailConfirmedAt == null) {
        await client.auth.signOut();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailNotVerifiedLoginScreen(
              email: user.email ?? 'your email',
            ),
          ),
        );

        return;
      }

      if (role == 'driver') {
        final driverData = await client
            .from('driver_profiles')
            .select('is_active, verification_status')
            .eq('id', user.id)
            .maybeSingle();

        final status = _driverStatus(driverData);

        if (driverData == null) {
          await client.auth.signOut();

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const AccountStatusScreen(
                status: 'pending',
              ),
            ),
          );

          return;
        }

        if (status != 'approved') {
          await client.auth.signOut();

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AccountStatusScreen(
                status: status,
              ),
            ),
          );

          return;
        }

        Navigator.pushReplacementNamed(
          context,
          '/driver_dashboard',
        );

        return;
      }

      if (role == 'commuter') {
        try {
          if (isNewAuthFlow) {
            await client
                .from('commuter_profiles')
                .update({
                  'is_verified': true,
                })
                .eq('id', user.id);
          }
        } catch (e) {
          debugPrint(
            'Commuter verification update failed: $e',
          );
        }

        if (!mounted) return;

        Navigator.pushReplacementNamed(
          context,
          '/navigation_bar',
        );

        return;
      }

      await client.auth.signOut();

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/login',
      );
    } catch (e, stackTrace) {
      debugPrint('SPLASH AUTH ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');

      await client.auth.signOut();

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/login',
      );
    }
  }

  String _driverStatus(Map<String, dynamic>? data) {
    if (data == null) {
      return 'pending';
    }

    final explicitStatus =
        data['verification_status']?.toString().trim().toLowerCase();

    if (explicitStatus != null && explicitStatus.isNotEmpty) {
      return explicitStatus;
    }

    if (data['is_active'] == true) {
      return 'approved';
    }

    return 'pending';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF119400),
      body: Center(
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
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'RTODA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}