import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
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
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _body = TextEditingController();
  final _license = TextEditingController();
  final _phone = TextEditingController();

  bool _driver = true;
  bool _loading = false;
  bool _showPass = false;

  File? _profile;
  File? _id;

  @override
  void dispose() {
    for (final c in [
      _email,
      _password,
      _confirm,
      _name,
      _body,
      _license,
      _phone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ============================================================
  // IMAGE PICKER
  // ============================================================
  Future<void> _pick(bool profile) async {
    if (_loading) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted) return;

      setState(() {
        if (profile) {
          _profile = File(image.path);
        } else {
          _id = File(image.path);
        }
      });
    } catch (e) {
      debugPrint('PICK IMAGE ERROR: $e');
      if (mounted) _error('Could not select image.');
    }
  }

  // ============================================================
  // SIGNUP
  // ============================================================
  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_profile == null) {
      _error('Please upload your profile photo.');
      return;
    }
    if (_id == null) {
      _error(
        _driver
            ? "Please upload your driver's license."
            : 'Please upload a valid ID.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    final fullName = _name.text.trim();
    final phoneNumber = _phone.text.trim().replaceAll(RegExp(r'[^\d+]'), '');
    final bodyNumber = _driver
        ? 'VGN-${_body.text.trim()}'.toUpperCase()
        : null;
    final licenseNumber = _driver ? _license.text.trim().toUpperCase() : null;

    try {
      if (_driver) {
        await _signupDriver(
          email: email,
          password: password,
          fullName: fullName,
          phoneNumber: phoneNumber,
          bodyNumber: bodyNumber!,
          licenseNumber: licenseNumber!,
        );
        return;
      }

      await _signupCommuter(
        email: email,
        password: password,
        fullName: fullName,
        phoneNumber: phoneNumber,
      );
    } on AuthException catch (e) {
      if (_isExisting(e.message)) {
        await _existingAccount(email);
      } else {
        if (mounted) _error(_authMessage(e.message));
      }
    } on FunctionException catch (e) {
      debugPrint(
        'driver-signup FunctionException: '
        '${e.status} ${e.details}',
      );

      String message = 'Unable to create driver account.';
      if (e.details is Map) {
        final details = Map<String, dynamic>.from(e.details as Map);
        message =
            details['error']?.toString() ??
            details['message']?.toString() ??
            message;
      } else if (e.details != null) {
        message = e.details.toString();
      }
      if (mounted) _error(message);
    } catch (e) {
      debugPrint('Signup error: $e');
      if (mounted) {
        _error(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signupDriver({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String bodyNumber,
    required String licenseNumber,
  }) async {
    final functionResponse = await client.functions.invoke(
      'hyper-responder',
      body: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'phone_number': phoneNumber,
        'body_number': bodyNumber,
        'license_number': licenseNumber,
      },
    );

    final responseData = functionResponse.data;
    if (responseData == null || responseData is! Map) {
      throw Exception(
        'No valid response was received from the driver signup service.',
      );
    }

    final data = Map<String, dynamic>.from(responseData);
    if (data['success'] != true) {
      throw Exception(
        data['error']?.toString() ?? 'Unable to create driver account.',
      );
    }

    final userId = data['user_id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw Exception(
        'Driver account was created, but no user ID was returned.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_registration_uid', userId);
    await prefs.setString('pending_registration_role', 'driver');
    await prefs.setString('pending_registration_email', email);
    await prefs.setString('pending_full_name', fullName);
    await prefs.setString('pending_phone_number', phoneNumber);
    await prefs.setString('pending_body_number', bodyNumber);
    await prefs.setString('pending_license_number', licenseNumber);
    await prefs.setString('pending_profile_image_path', _profile!.path);
    await prefs.setString('pending_id_image_path', _id!.path);

    final loginResponse = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (loginResponse.user == null) {
      throw Exception(
        'Driver account was created, but automatic login failed.',
      );
    }

    try {
      await _completeProfile(userId, 'driver');
    } finally {
      await client.auth.signOut();
    }

    if (!mounted) return;
    _message(
      'Driver account created successfully. '
      'Please wait for RTODA/LGU approval.',
    );

    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _signupCommuter({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'rtoda://login-callback',
      data: {
        'rtoda_auth_v2': true,
        'role': 'commuter',
        'full_name': fullName,
        'phone_number': phoneNumber,
      },
    );

    final user = response.user;
    if (user == null) {
      throw const AuthException('Unable to create account.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_registration_uid', user.id);
    await prefs.setString('pending_registration_role', 'commuter');
    await prefs.setString('pending_registration_email', email);
    await prefs.setString('pending_full_name', fullName);
    await prefs.setString('pending_phone_number', phoneNumber);
    await prefs.setString('pending_profile_image_path', _profile!.path);
    await prefs.setString('pending_id_image_path', _id!.path);

    if (response.session == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(email: email),
        ),
      );
      return;
    }

    await _completeProfile(user.id, 'commuter');

    if (!mounted) return;

    final confirmed = client.auth.currentUser?.emailConfirmedAt != null;
    if (confirmed) {
      Navigator.pushReplacementNamed(context, '/navigation_bar');
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(email: email),
        ),
      );
    }
  }

  // ============================================================
  // ERROR CLASSIFICATION
  // ============================================================
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
            child: const Text('RESEND VERIFICATION'),
          ),
          FilledButton(
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
      await client.auth.resend(type: OtpType.signup, email: email);
      if (!mounted) return;
      _message('Verification email sent to $email.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(email: email),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) _error(e.message);
    }
  }

  // ============================================================
  // PROFILE CREATION
  // ============================================================
  Future<void> _completeProfile(String uid, String role) async {
    final prefs = await SharedPreferences.getInstance();

    final savedName = prefs.getString('pending_full_name') ?? _name.text.trim();
    final savedPhone =
        prefs.getString('pending_phone_number') ?? _phone.text.trim();
    final savedBody =
        prefs.getString('pending_body_number') ??
        'VGN-${_body.text.trim()}'.toUpperCase();
    final savedLicense =
        prefs.getString('pending_license_number') ??
        _license.text.trim().toUpperCase();
    final profilePath = prefs.getString('pending_profile_image_path');
    final idPath = prefs.getString('pending_id_image_path');

    Future<String?> upload(String? path, String bucket, String folder) async {
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        return null;
      }
      final ext = path.split('.').last.toLowerCase();
      final storagePath = '$folder/$uid.$ext';

      await client.storage
          .from(bucket)
          .upload(
            storagePath,
            File(path),
            fileOptions: FileOptions(upsert: true, contentType: _mimeFor(ext)),
          );

      return client.storage.from(bucket).getPublicUrl(storagePath);
    }

    final profileUrl = await upload(
      profilePath,
      'user_profiles',
      role == 'driver' ? 'drivers' : 'commuters',
    );
    final verificationUrl = await upload(
      idPath,
      'id-verifications',
      role == 'driver' ? 'drivers_license' : 'commuter_ids',
    );

    if (verificationUrl == null) {
      throw Exception(
        role == 'driver'
            ? 'Required license photo is missing.'
            : 'Required ID photo is missing.',
      );
    }

    if (role == 'driver') {
      final data = <String, dynamic>{
        'id': uid,
        'full_name': savedName,
        'phone_number': savedPhone,
        'license_number': savedLicense,
        'body_number': savedBody,
        'is_active': false,
        'rating': 5.0,
        'verification_status': 'pending',
        'license_photo_url': verificationUrl,
        if (profileUrl != null) 'profile_photo_url': profileUrl,
      };

      await client.from('driver_profiles').upsert(data, onConflict: 'id');
    } else {
      final data = <String, dynamic>{
        'id': uid,
        'full_name': savedName,
        'phone_number': savedPhone,
        'id_photo_url': verificationUrl,
        'is_verified': client.auth.currentUser?.emailConfirmedAt != null,
        if (profileUrl != null) 'profile_photo_url': profileUrl,
      };

      await client.from('commuter_profiles').upsert(data, onConflict: 'id');
    }

    for (final key in [
      'pending_registration_uid',
      'pending_registration_role',
      'pending_registration_email',
      'pending_full_name',
      'pending_phone_number',
      'pending_body_number',
      'pending_license_number',
      'pending_profile_image_path',
      'pending_id_image_path',
    ]) {
      await prefs.remove(key);
    }
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  // ============================================================
  // SNACKBARS
  // ============================================================
  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _message(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    // ── Role selector ─────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _role(
                            'Driver',
                            _driver,
                            Icons.local_taxi,
                            () => setState(() => _driver = true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _role(
                            'Commuter',
                            !_driver,
                            Icons.person,
                            () => setState(() => _driver = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      _driver
                          ? 'Driver accounts require RTODA/LGU verification.'
                          : 'Commuter accounts require email verification.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Photos ────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _imageTile(
                          label: 'Profile *',
                          file: _profile,
                          onTap: () => _pick(true),
                        ),
                        _imageTile(
                          label: _driver ? 'License *' : 'Valid ID *',
                          file: _id,
                          onTap: () => _pick(false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Fields ────────────────────────────────
                    _field(
                      _name,
                      'Full Name',
                      Icons.person_outline,
                      textCapitalization: TextCapitalization.words,
                      action: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                    ),
                    const SizedBox(height: 16),
                    _field(
                      _phone,
                      'Phone Number',
                      Icons.phone_outlined,
                      number: true,
                      action: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                    ),

                    if (_driver) ...[
                      const SizedBox(height: 16),
                      _bodyField(),
                      const SizedBox(height: 16),
                      _field(
                        _license,
                        'License Number',
                        Icons.badge_outlined,
                        textCapitalization: TextCapitalization.characters,
                        action: TextInputAction.next,
                        formatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9\-]'),
                          ),
                          LengthLimitingTextInputFormatter(30),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    _field(
                      _email,
                      'Email',
                      Icons.email_outlined,
                      keyboard: TextInputType.emailAddress,
                      action: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      formatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _field(
                      _password,
                      'Password',
                      Icons.lock_outline,
                      obscure: true,
                      action: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      helper: 'At least 8 characters',
                    ),
                    const SizedBox(height: 16),
                    _field(
                      _confirm,
                      'Confirm Password',
                      Icons.lock_outline,
                      obscure: true,
                      action: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (v != _password.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── Submit ────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _signup,
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
                                'CREATE ACCOUNT',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.pushReplacementNamed(
                              context,
                              '/login',
                            ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.green,
                      ),
                      child: const Text(
                        'Already have an account? Log in',
                        style: TextStyle(fontWeight: FontWeight.w600),
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

  // ============================================================
  // SUB-WIDGETS
  // ============================================================
  Widget _role(String title, bool selected, IconData icon, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title account',
      child: GestureDetector(
        onTap: _loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected ? AppColors.greenSoft : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.green : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.green : AppColors.muted),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: selected ? AppColors.greenDark : AppColors.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageTile({
    required String label,
    required File? file,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: 'Upload $label photo',
          child: GestureDetector(
            onTap: _loading ? null : onTap,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: file == null
                  ? const Icon(
                      Icons.add_a_photo_outlined,
                      size: 32,
                      color: AppColors.green,
                    )
                  : Image.file(file, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }

  Widget _bodyField() {
    return TextFormField(
      controller: _body,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(5),
      ],
      validator: (v) {
        final digits = (v ?? '').trim();
        if (digits.isEmpty) return 'Body number is required';
        if (!RegExp(r'^\d{1,5}$').hasMatch(digits)) {
          return 'Enter the digits only';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Body Number',
        prefixText: 'VGN- ',
        prefixIcon: const Icon(Icons.directions_bus, color: AppColors.green),
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
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    bool number = false,
    TextInputType? keyboard,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? action,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? formatters,
    String? helper,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure && !_showPass,
      keyboardType:
          keyboard ?? (number ? TextInputType.phone : TextInputType.text),
      textCapitalization: textCapitalization,
      textInputAction: action,
      autofillHints: autofillHints,
      inputFormatters: formatters,
      validator:
          validator ??
          (value) {
            final v = value?.trim() ?? '';

            if (v.isEmpty) return '$label is required';

            if (label == 'Email' &&
                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
              return 'Enter a valid email';
            }

            if (label == 'Password' && value!.length < 8) {
              return 'Use at least 8 characters';
            }

            if (label == 'Phone Number') {
              final digits = v.replaceAll(RegExp(r'[^\d+]'), '');
              if (!RegExp(r'^(09\d{9}|\+?639\d{9})$').hasMatch(digits)) {
                return 'Enter a valid PH number (e.g., 0917 123 4567)';
              }
            }

            return null;
          },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: Icon(icon, color: AppColors.green),
        suffixIcon: obscure
            ? IconButton(
                tooltip: _showPass ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPass = !_showPass),
                icon: Icon(
                  _showPass ? Icons.visibility : Icons.visibility_off,
                  color: AppColors.muted,
                ),
              )
            : null,
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
      ),
    );
  }
}
