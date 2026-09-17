import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fcm_service.dart';
import 'account_status_screen.dart';
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
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

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

      debugPrint('LOGIN USER: ${user.id}');

      final role = await _getRole(user.id);

      if (role == null) {
        await _signOut();

        throw const AuthException(
          'Your RTODA account role could not be found. '
          'Please contact support.',
        );
      }

      debugPrint('LOGIN ROLE: $role');

      final isNewAuth = user.userMetadata?['rtoda_auth_v2'] == true;

      if (isNewAuth && user.emailConfirmedAt == null) {
        await _signOut();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailNotVerifiedLoginScreen(
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

      throw const AuthException(
        'Unknown account role. Please contact support.',
      );
    } on AuthException catch (e) {
      debugPrint('AUTH ERROR: ${e.message}');

      if (!mounted) return;

      final message = e.message.toLowerCase().contains('email not confirmed')
          ? 'Please verify your email before logging in.'
          : e.message;

      _error(message);
    } catch (e, stackTrace) {
      debugPrint('LOGIN ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');

      await _signOut();

      if (!mounted) return;

      _error('Login failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _getRole(String uid) async {
    final data = await client
        .from('user_roles')
        .select('role')
        .eq('id', uid)
        .maybeSingle();

    if (data == null) return null;

    final role = data['role']?.toString().trim().toLowerCase();

    if (role == 'driver' || role == 'commuter') {
      return role;
    }

    return null;
  }

  Future<void> _handleDriverLogin(String uid) async {
    debugPrint('CHECKING DRIVER PROFILE: $uid');

    final profile = await client
        .from('driver_profiles')
        .select(
          'id, full_name, license_number, body_number, '
          'is_active, rating, created_at, profile_photo_url, '
          'license_photo_url, phone_number, verification_status',
        )
        .eq('id', uid)
        .maybeSingle();

    debugPrint('DRIVER PROFILE: $profile');

    if (profile == null) {
      await _signOut();

      if (!mounted) return;

      _error('Driver profile not found. Please contact support.');
      return;
    }

    final status = _driverStatus(profile);
    final active = profile['is_active'] == true;

    debugPrint('DRIVER STATUS: $status');
    debugPrint('DRIVER ACTIVE: $active');

    if (!active) {
      await _signOut();
      await _showAccountStatus('inactive');
      return;
    }

    if (status != 'approved') {
      await _signOut();
      await _showAccountStatus(status);
      return;
    }

    await _initializeFcm('driver');

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/driver_dashboard');
  }

  String _driverStatus(Map<String, dynamic>? data) {
    if (data == null) return 'pending';

    final status = data['verification_status']?.toString().trim().toLowerCase();

    if (status == 'approved' || status == 'pending' || status == 'rejected') {
      return status!;
    }

    if (data['is_active'] == true) {
      return 'approved';
    }

    return 'pending';
  }

  Future<void> _refreshDriverStatus(String uid) async {
    try {
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
        if (!mounted) return;

        _error('Driver profile not found.');
        return;
      }

      final status = _driverStatus(profile);
      final active = profile['is_active'] == true;

      if (!mounted) return;

      if (status == 'approved' && active) {
        Navigator.pushReplacementNamed(context, '/driver_dashboard');
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AccountStatusScreen(status: status),
          ),
        );
      }
    } catch (e) {
      debugPrint('REFRESH DRIVER STATUS ERROR: $e');

      if (!mounted) return;

      _error('Unable to check account status.');
    }
  }

  Future<void> _finishPendingRegistration(
    String uid,
    String role,
    Map<String, dynamic> metadata,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final pendingUid = prefs.getString('pending_registration_uid');

    if (role == 'commuter') {
      try {
        final existing = await client
            .from('commuter_profiles')
            .select('id')
            .eq('id', uid)
            .maybeSingle();

        if (existing == null) {
          String? profileUrl;
          String? verificationUrl;

          if (pendingUid == uid) {
            final profilePath = prefs.getString('pending_profile_image_path');

            final idPath = prefs.getString('pending_id_image_path');

            profileUrl = await _uploadImage(
              path: profilePath,
              bucket: 'user_profiles',
              folder: 'commuters',
              uid: uid,
            );

            verificationUrl = await _uploadImage(
              path: idPath,
              bucket: 'id-verifications',
              folder: 'commuter_ids',
              uid: uid,
            );
          }

          final data = <String, dynamic>{
            'id': uid,
            'full_name': _meta(metadata, 'full_name'),
            'phone_number': _meta(metadata, 'phone_number'),
            'is_verified': false,
          };

          if (verificationUrl != null) {
            data['id_photo_url'] = verificationUrl;
          }

          if (profileUrl != null) {
            data['profile_photo_url'] = profileUrl;
          }

          await client.from('commuter_profiles').insert(data);
        }

        if (pendingUid == uid) {
          await _clearPendingRegistration();
        }
      } catch (e, stackTrace) {
        debugPrint('COMMUTER PROFILE CREATE ERROR: $e');
        debugPrint('STACK TRACE: $stackTrace');
        rethrow;
      }

      return;
    }

    if (pendingUid != uid) return;

    final profilePath = prefs.getString('pending_profile_image_path');

    final idPath = prefs.getString('pending_id_image_path');

    String? profileUrl;
    String? verificationUrl;

    try {
      profileUrl = await _uploadImage(
        path: profilePath,
        bucket: 'user_profiles',
        folder: 'drivers',
        uid: uid,
      );

      verificationUrl = await _uploadImage(
        path: idPath,
        bucket: 'id-verifications',
        folder: 'drivers_license',
        uid: uid,
      );

      await _createDriverProfile(uid, metadata, profileUrl, verificationUrl);

      await _clearPendingRegistration();
    } catch (e, stackTrace) {
      debugPrint('DRIVER PROFILE CREATE ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');
      rethrow;
    }
  }

  Future<String?> _uploadImage({
    required String? path,
    required String bucket,
    required String folder,
    required String uid,
  }) async {
    if (path == null || !File(path).existsSync()) {
      return null;
    }

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

    if (profileUrl != null) {
      data['profile_photo_url'] = profileUrl;
    }

    await client.from('driver_profiles').upsert(data, onConflict: 'id');
  }

  Future<void> _createCommuterProfile(
    String uid,
    Map<String, dynamic> metadata,
    String? profileUrl,
    String? idUrl,
  ) async {
    if (idUrl == null) {
      throw Exception('Commuter ID photo was not found.');
    }

    final data = <String, dynamic>{
      'id': uid,
      'full_name': _meta(metadata, 'full_name'),
      'phone_number': _meta(metadata, 'phone_number'),
      'id_photo_url': idUrl,
      'is_verified': false,
    };

    if (profileUrl != null) {
      data['profile_photo_url'] = profileUrl;
    }

    await client.from('commuter_profiles').upsert(data, onConflict: 'id');
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

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();

    if (!email.contains('@')) {
      _error('Enter your email first.');
      return;
    }

    setState(() => _resetting = true);

    try {
      await client.auth.resetPasswordForEmail(email);

      if (!mounted) return;

      _message('Password reset email sent.');
    } on AuthException catch (e) {
      if (mounted) _error(e.message);
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  InputDecoration _input(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.black12),
      ),
    );
  }

  void _error(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Image.asset(
                  'assets/images/app_icon.png',
                  width: 90,
                  height: 90,
                ),
                const SizedBox(height: 14),
                const Text(
                  'RTODA Vigan',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Report • Monitor • Protect',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 28),
                _loginCard(),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  ),
                  child: const Text("Don't have an account? Create one"),
                ),
              ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
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
                onPressed: () {
                  setState(() {
                    _showPassword = !_showPassword;
                  });
                },
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resetting ? null : _forgotPassword,
              child: Text(_resetting ? 'Sending...' : 'Forgot password?'),
            ),
          ),
        ],
      ),
    );
  }
}

class EmailNotVerifiedLoginScreen extends StatelessWidget {
  final String email;

  const EmailNotVerifiedLoginScreen({super.key, required this.email});

  Future<void> _resend(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent again.')),
      );
    } on AuthException catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('Email Verification'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  size: 50,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verify your email first',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'A verification link was sent to:\n$email',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Text(
                  'Open your email and tap the verification link. '
                  'After verification, return to RTODA and log in again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.5),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _resend(context),
                  icon: const Icon(Icons.refresh),
                  label: const Text('RESEND VERIFICATION'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('BACK TO LOGIN'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
