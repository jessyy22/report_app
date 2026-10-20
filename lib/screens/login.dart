import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../services/fcm_service.dart';
import 'account_status_screen.dart';
import 'email_verification_screen.dart';
import 'register.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _resetting = false;

  SupabaseClient get client => Supabase.instance.client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Show any message passed from ResetPasswordScreen (or other screens).
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['message'] is String) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _message(args['message'] as String);
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // ============================================================
  // LOGIN
  // ============================================================
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final response = await client.auth.signInWithPassword(
        email: _email.text.trim().toLowerCase(),
        password: _password.text,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthException('Authentication failed.');
      }

      final role = await _getRole(user.id);

      if (role == null) {
        await _signOut();
        if (!mounted) return;
        _error(
          'Your RTODA account role could not be found. '
          'Please contact support.',
        );
        return;
      }

      final isNewAuth = user.userMetadata?['rtoda_auth_v2'] == true;

      if (isNewAuth && user.emailConfirmedAt == null) {
        await _signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(
              email: user.email ?? _email.text.trim(),
            ),
          ),
        );
        return;
      }

      await _finishPendingRegistration(user.id, role, user.userMetadata ?? {});

      if (role == 'driver') {
        await _handleDriverLogin(user.id);
        return;
      }

      if (role == 'commuter') {
        await _initializeFcm('commuter');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/navigation_bar');
        return;
      }

      await _signOut();
      if (!mounted) return;
      _error('Unknown account role. Please contact support.');
    } on AuthException catch (e) {
      debugPrint('AUTH ERROR: ${e.message}');
      if (!mounted) return;

      final raw = e.message.toLowerCase();
      String message;

      if (raw.contains('email not confirmed')) {
        message = 'Please verify your email before logging in.';
      } else if (raw.contains('invalid login credentials') ||
          raw.contains('invalid_credentials')) {
        message = 'Incorrect email or password. Please try again.';
      } else if (raw.contains('rate limit') || raw.contains('too many')) {
        message = 'Too many attempts. Please wait a moment and try again.';
      } else {
        message = e.message;
      }

      _error(message);
    } catch (e, stackTrace) {
      debugPrint('LOGIN ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');
      if (!mounted) return;
      _error('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ============================================================
  // ROLE LOOKUP
  // ============================================================
  Future<String?> _getRole(String uid) async {
    final data = await client
        .from('user_roles')
        .select('role')
        .eq('id', uid)
        .maybeSingle();

    if (data == null) return null;
    final role = data['role']?.toString().trim().toLowerCase();
    if (role == 'driver' || role == 'commuter') return role;
    return null;
  }

  // ============================================================
  // DRIVER LOGIN
  // ============================================================
  Future<void> _handleDriverLogin(String uid) async {
    final profile = await client
        .from('driver_profiles')
        .select(
          'id, full_name, license_number, body_number, '
          'is_active, rating, created_at, profile_photo_url, '
          'license_photo_url, phone_number, verification_status',
        )
        .eq('id', uid)
        .maybeSingle();

    if (profile == null) {
      await _signOut();
      if (!mounted) return;
      _error('Driver profile not found. Please contact support.');
      return;
    }

    final status = _driverStatus(profile);
    final active = profile['is_active'] == true;

    if (status != 'approved') {
      await _signOut();
      await _showAccountStatus(status);
      return;
    }

    if (!active) {
      await _signOut();
      await _showAccountStatus('inactive');
      return;
    }

    await _initializeFcm('driver');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/driver_dashboard');
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

  // ============================================================
  // PENDING REGISTRATION COMPLETION
  // ============================================================
  Future<void> _finishPendingRegistration(
    String uid,
    String role,
    Map<String, dynamic> metadata,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingUid = prefs.getString('pending_registration_uid');

    if (role == 'commuter') {
      final existing = await client
          .from('commuter_profiles')
          .select('id')
          .eq('id', uid)
          .maybeSingle();

      final emailVerified = client.auth.currentUser?.emailConfirmedAt != null;

      if (existing == null) {
        String? profileUrl;
        String? verificationUrl;

        if (pendingUid == uid) {
          profileUrl = await _uploadImage(
            path: prefs.getString('pending_profile_image_path'),
            bucket: 'user_profiles',
            folder: 'commuters',
            uid: uid,
          );
          verificationUrl = await _uploadImage(
            path: prefs.getString('pending_id_image_path'),
            bucket: 'id-verifications',
            folder: 'commuter_ids',
            uid: uid,
          );
        }

        final data = <String, dynamic>{
          'id': uid,
          'full_name': _meta(metadata, 'full_name'),
          'phone_number': _meta(metadata, 'phone_number'),
          'is_verified': emailVerified,
        };
        if (verificationUrl != null) {
          data['id_photo_url'] = verificationUrl;
        }
        if (profileUrl != null) {
          data['profile_photo_url'] = profileUrl;
        }

        await client.from('commuter_profiles').insert(data);
      } else {
        await client
            .from('commuter_profiles')
            .update({'is_verified': emailVerified})
            .eq('id', uid);
      }

      if (pendingUid == uid) await _clearPendingRegistration();
      return;
    }

    if (pendingUid != uid) return;

    final profileUrl = await _uploadImage(
      path: prefs.getString('pending_profile_image_path'),
      bucket: 'user_profiles',
      folder: 'drivers',
      uid: uid,
    );
    final verificationUrl = await _uploadImage(
      path: prefs.getString('pending_id_image_path'),
      bucket: 'id-verifications',
      folder: 'drivers_license',
      uid: uid,
    );

    await _createDriverProfile(uid, metadata, profileUrl, verificationUrl);
    await _clearPendingRegistration();
  }

  Future<String?> _uploadImage({
    required String? path,
    required String bucket,
    required String folder,
    required String uid,
  }) async {
    if (path == null || !File(path).existsSync()) return null;

    final extension = path.split('.').last.toLowerCase();
    final storagePath = '$folder/$uid.$extension';

    await client.storage
        .from(bucket)
        .upload(
          storagePath,
          File(path),
          fileOptions: const FileOptions(upsert: true),
        );

    return client.storage.from(bucket).getPublicUrl(storagePath);
  }

  Future<void> _createDriverProfile(
    String uid,
    Map<String, dynamic> metadata,
    String? profileUrl,
    String? licenseUrl,
  ) async {
    if (licenseUrl == null) {
      throw Exception('Driver license photo was not found.');
    }

    final data = <String, dynamic>{
      'id': uid,
      'full_name': _meta(metadata, 'full_name'),
      'phone_number': _meta(metadata, 'phone_number'),
      'license_number': _meta(metadata, 'license_number'),
      'body_number': _meta(metadata, 'body_number'),
      'is_active': false,
      'rating': 5.0,
      'verification_status': 'pending',
      'license_photo_url': licenseUrl,
    };
    if (profileUrl != null) data['profile_photo_url'] = profileUrl;

    await client.from('driver_profiles').upsert(data, onConflict: 'id');
  }

  String _meta(Map<String, dynamic> metadata, String key) {
    return (metadata[key] ?? '').toString().trim();
  }

  Future<void> _clearPendingRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'pending_registration_uid',
      'pending_registration_role',
      'pending_registration_email',
      'pending_profile_image_path',
      'pending_id_image_path',
    ]) {
      await prefs.remove(key);
    }
  }

  // ============================================================
  // FCM / SIGN OUT / STATUS
  // ============================================================
  Future<void> _initializeFcm(String role) async {
    try {
      await FcmService().initialize();
      debugPrint('FCM initialized for $role.');
    } catch (e) {
      debugPrint('FCM initialization failed for $role: $e');
    }
  }

  Future<void> _showAccountStatus(String status) async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AccountStatusScreen(status: status)),
    );
  }

  Future<void> _signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      debugPrint('SIGN OUT ERROR: $e');
    }
  }

  // ============================================================
  // FORGOT PASSWORD
  // ============================================================
  Future<void> _forgotPassword() async {
    final email = _email.text.trim().toLowerCase();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _error('Enter a valid email first.');
      return;
    }

    setState(() => _resetting = true);

    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'rtoda://reset-password', // ← make sure this matches
      );

      if (!mounted) return;

      _message(
        'If an account exists for this email, a password reset link '
        'has been sent.',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _error(e.message);
    } catch (e) {
      if (!mounted) return;
      _error('Unable to send password reset email.');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  // ============================================================
  // SNACKBARS
  // ============================================================
  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================
  InputDecoration _input(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.green),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.green, width: 1.5),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/app_icon.png',
                      width: 90,
                      height: 90,
                      semanticLabel: 'RTODA Vigan logo',
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.local_police,
                        size: 80,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'RTODA Vigan',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Report • Monitor • Protect',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 28),
                    _loginCard(),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'LOGIN',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupPage()),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.green,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                      child: const Text(
                        "Don't have an account? Create one",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'By logging in, you agree to our Terms and Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _email,
            enabled: !_resetting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.none,
            autofillHints: const [AutofillHints.email],
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            validator: (value) {
              final email = value?.trim() ?? '';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Enter a valid email';
              }
              return null;
            },
            decoration: _input('Email', Icons.email_outlined),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 128,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) {
              if (!_loading) _login();
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Password is required';
              }
              return null;
            },
            decoration: _input(
              'Password',
              Icons.lock_outline,
              suffix: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () {
                  setState(() => _showPassword = !_showPassword);
                },
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                  color: AppColors.muted,
                ),
              ),
            ).copyWith(counterText: ''),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resetting ? null : _forgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.green,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),
              child: Text(
                _resetting ? 'Sending...' : 'Forgot password?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
