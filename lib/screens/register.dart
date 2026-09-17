import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'email_verification_screen.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final SupabaseClient client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _body = TextEditingController();
  final _license = TextEditingController();
  final _phone = TextEditingController();

  bool _driver = true, _loading = false, _showPass = false;
  File? _profile, _id;

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _body, _license, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool profile) async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Image Source'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Gallery'),
          ),
        ],
      ),
    );

    if (source == null) return;

    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
    );

    if (image == null || !mounted) return;

    setState(() {
      if (profile) {
        _profile = File(image.path);
      } else {
        _id = File(image.path);
      }
    });
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_profile == null || _id == null) {
      return _error('Please select both required photos.');
    }

    setState(() => _loading = true);

    final supabase = Supabase.instance.client;
    final email = _email.text.trim().toLowerCase();
    final role = _driver ? 'driver' : 'commuter';

    try {
      final response = await client.auth.signUp(
        email: email,
        password: _password.text,
        emailRedirectTo: 'rtoda://login-callback',
        data: {
          'rtoda_auth_v2': true,
          'role': role,
          'full_name': _name.text.trim(),
          'phone_number': _phone.text.trim(),
          'body_number': _driver ? _body.text.trim() : null,
          'license_number': _driver ? _license.text.trim() : null,
        },
      );

      final user = response.user;
      if (user == null) {
        throw const AuthException('Unable to create account.');
      }

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('pending_registration_uid', user.id);
      await prefs.setString('pending_registration_role', role);
      await prefs.setString('pending_registration_email', email);
      await prefs.setString('pending_profile_image_path', _profile!.path);
      await prefs.setString('pending_id_image_path', _id!.path);

      if (response.session != null) {
        await _completeProfile(user.id, role);
      }

      if (!mounted) return;

      if (response.session == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(email: email),
          ),
        );
      } else if (_driver) {
        await supabase.auth.signOut();
        _message('Driver account created. Please wait for RTODA/LGU approval.');

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        Navigator.pushReplacementNamed(context, '/navigation_bar');
      }
    } on AuthException catch (e) {
      if (_isExisting(e.message)) {
        await _existingAccount(email);
      } else {
        _error(_authMessage(e.message));
      }
    } catch (e) {
      debugPrint('Signup error: $e');
      _error('Registration failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _isExisting(String msg) {
    final m = msg.toLowerCase();

    return m.contains('already registered') ||
        m.contains('already exists') ||
        m.contains('user already') ||
        m.contains('duplicate');
  }

  String _authMessage(String msg) {
    final m = msg.toLowerCase();

    if (m.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }

    if (m.contains('password')) {
      return 'Your password does not meet the requirements.';
    }

    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Please wait and try again.';
    }

    if (m.contains('network') || m.contains('connection')) {
      return 'Please check your internet connection.';
    }

    return msg;
  }

  Future<void> _existingAccount(String email) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Account Already Exists'),
        content: Text(
          '$email is already registered.\n\n'
          'You can log in or request another verification email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'verify'),
            child: const Text('RESEND'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'login'),
            child: const Text('LOGIN'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;

    if (action == 'login') {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );

      if (!mounted) return;

      _message('Verification email sent to $email.');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(email: email),
        ),
      );
    } on AuthException catch (e) {
      _error(e.message);
    }
  }

  Future<void> _completeProfile(String uid, String role) async {
    final supabase = Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();

    final profilePath = prefs.getString('pending_profile_image_path');
    final idPath = prefs.getString('pending_id_image_path');

    String? profileUrl;
    String? verificationUrl;

    Future<String?> upload(String? path, String bucket, String folder) async {
      if (path == null || !File(path).existsSync()) {
        return null;
      }

      final ext = path.split('.').last.toLowerCase();
      final storagePath = '$folder/$uid.$ext';

      await supabase.storage
          .from(bucket)
          .upload(
            storagePath,
            File(path),
            fileOptions: const FileOptions(upsert: true),
          );

      return supabase.storage.from(bucket).getPublicUrl(storagePath);
    }

    profileUrl = await upload(
      profilePath,
      'user_profiles',
      role == 'driver' ? 'drivers' : 'commuters',
    );

    verificationUrl = await upload(
      idPath,
      'id-verifications',
      role == 'driver' ? 'drivers_license' : 'commuter_ids',
    );

    if (verificationUrl == null) {
      throw Exception('Required ID/license photo is missing.');
    }

    if (role == 'driver') {
      final data = {
        'id': uid,
        'full_name': _name.text.trim(),
        'phone_number': _phone.text.trim(),
        'license_number': _license.text.trim(),
        'body_number': _body.text.trim(),
        'is_active': false,
        'rating': 5.0,
        'verification_status': 'pending',
        if (profileUrl != null) 'profile_photo_url': profileUrl,
        'license_photo_url': verificationUrl,
      };

      await supabase.from('driver_profiles').upsert(data, onConflict: 'id');
    } else {
      final data = {
        'id': uid,
        'full_name': _name.text.trim(),
        'phone_number': _phone.text.trim(),
        'id_photo_url': verificationUrl,
        'is_verified': false,
        if (profileUrl != null) 'profile_photo_url': profileUrl,
      };

      await supabase.from('commuter_profiles').upsert(data, onConflict: 'id');
    }

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

  void _error(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _message(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _role(
                      'Driver',
                      _driver,
                      () => setState(() => _driver = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _role(
                      'Commuter',
                      !_driver,
                      () => setState(() => _driver = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _driver
                    ? 'Driver accounts require RTODA/LGU verification.'
                    : 'Commuter accounts require email verification.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _image('Profile', _profile, () => _pick(true)),
                  _image(_driver ? 'License' : 'ID', _id, () => _pick(false)),
                ],
              ),
              const SizedBox(height: 24),
              _field(_name, 'Full Name', Icons.person_outline),
              const SizedBox(height: 16),
              _field(
                _phone,
                'Phone Number',
                Icons.phone_outlined,
                number: true,
              ),
              if (_driver) ...[
                const SizedBox(height: 16),
                _field(_body, 'Body Number (VGN-XXX)', Icons.directions_bus),
                const SizedBox(height: 16),
                _field(_license, 'License Number', Icons.badge_outlined),
              ],
              const SizedBox(height: 16),
              _field(
                _email,
                'Email',
                Icons.email_outlined,
                keyboard: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _field(_password, 'Password', Icons.lock_outline, obscure: true),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signup,
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
                          'CREATE ACCOUNT',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _role(String title, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? Colors.green.withOpacity(.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.green : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              title == 'Driver' ? Icons.local_taxi : Icons.person,
              color: selected ? Colors.green : Colors.black45,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(String label, File? file, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 120,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: file == null
                ? const Icon(
                    Icons.add_a_photo_outlined,
                    size: 34,
                    color: Colors.green,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Image.file(file, fit: BoxFit.cover),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    bool number = false,
    TextInputType? keyboard,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure && !_showPass,
      keyboardType:
          keyboard ?? (number ? TextInputType.phone : TextInputType.text),
      validator: (value) {
        final v = value?.trim() ?? '';

        if (v.isEmpty) {
          return '$label is required';
        }

        if (label == 'Email' &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
          return 'Enter a valid email';
        }

        if (label == 'Password' && value!.length < 8) {
          return 'Use at least 8 characters';
        }

        if (label == 'Phone Number' &&
            !RegExp(r'^(09|\+639)\d{9}$').hasMatch(v)) {
          return 'Enter a valid Philippine phone number';
        }

        if (label == 'Body Number (VGN-XXX)' &&
            !RegExp(r'^VGN-\d{3}$').hasMatch(v.toUpperCase())) {
          return 'Use format VGN-XXX';
        }

        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: obscure
            ? IconButton(
                onPressed: () => setState(() => _showPass = !_showPass),
                icon: Icon(_showPass ? Icons.visibility : Icons.visibility_off),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black12),
        ),
      ),
    );
  }
}
