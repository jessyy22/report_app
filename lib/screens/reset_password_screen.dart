import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _loading = false;
  bool _validating = true;
  bool _hasSession = false;

  SupabaseClient get client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _validateSession();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // ── Wait for recovery session to hydrate ─────────────────
  Future<void> _validateSession() async {
    // Poll for up to ~3s — Supabase may still be processing the URI
    for (var i = 0; i < 15; i++) {
      if (client.auth.currentSession != null) {
        if (!mounted) return;
        setState(() {
          _hasSession = true;
          _validating = false;
        });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted) return;
    setState(() {
      _hasSession = false;
      _validating = false;
    });
  }

  Future<void> _updatePassword() async {
    final password = _password.text;
    final confirm = _confirmPassword.text;

    if (password.length < 8) {
      _error('Password must be at least 8 characters.');
      return;
    }
    if (password != confirm) {
      _error('Passwords do not match.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      await client.auth.updateUser(UserAttributes(password: password));

      if (!mounted) return;

      // Best-effort sign out — don't fail the whole flow
      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('SIGN OUT AFTER RESET FAILED: $e');
      }

      if (!mounted) return;

      // Pass message via route arguments
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (_) => false,
        arguments: {'message': 'Password updated. Please log in again.'},
      );
    } on AuthException catch (e) {
      debugPrint('RESET AUTH ERROR: ${e.message}');
      if (!mounted) return;
      _error(e.message);
    } catch (e) {
      debugPrint('RESET ERROR: $e');
      if (!mounted) return;
      _error('Unable to update password. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  InputDecoration _input(
    String label,
    IconData icon, {
    Widget? suffix,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
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

  @override
  Widget build(BuildContext context) {
    // Show spinner while validating session
    if (_validating) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show error state if no valid session
    if (!_hasSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reset Password')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 56,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Reset link expired',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This reset link is invalid or has already been used. '
                    'Please request a new one from the login screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (_) => false,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back to Login'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Valid session — show password form
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: AppColors.greenSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        size: 40,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Create a New Password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your new password below. You will be '
                      'logged out after the update.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _password,
                      enabled: !_loading,
                      obscureText: !_showPassword,
                      enableSuggestions: false,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: _input(
                        'New Password',
                        Icons.lock_outline,
                        helper: 'At least 8 characters',
                        suffix: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: _loading
                              ? null
                              : () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPassword,
                      enabled: !_loading,
                      obscureText: !_showConfirmPassword,
                      enableSuggestions: false,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _updatePassword(),
                      decoration: _input(
                        'Confirm Password',
                        Icons.lock_outline,
                        suffix: IconButton(
                          tooltip: _showConfirmPassword
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: _loading
                              ? null
                              : () => setState(
                                  () => _showConfirmPassword =
                                      !_showConfirmPassword,
                                ),
                          icon: Icon(
                            _showConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _updatePassword,
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
                                'UPDATE PASSWORD',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
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
}
