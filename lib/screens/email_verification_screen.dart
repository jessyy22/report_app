import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _sending = false;
  bool _checking = false;

  DateTime? _lastResendTime;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // RESEND COOLDOWN
  // ============================================================
  int get _cooldownSeconds {
    if (_lastResendTime == null) return 0;
    final elapsed = DateTime.now().difference(_lastResendTime!).inSeconds;
    return elapsed >= 60 ? 0 : 60 - elapsed;
  }

  bool get _canResend => _cooldownSeconds == 0;

  // ============================================================
  // ACTIONS
  // ============================================================
  Future<void> _resend() async {
    if (_sending || !_canResend) return;

    setState(() => _sending = true);

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );

      if (!mounted) return;

      _lastResendTime = DateTime.now();
      _startCooldownTimer();

      _showSnack('Verification email sent again. Please check your inbox.');
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        'Unable to resend the verification email. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldownSeconds == 0) {
        t.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _continueToLogin() async {
    if (_checking) return;
    setState(() => _checking = true);

    try {
      // Refresh session to get the latest emailConfirmedAt
      await Supabase.instance.client.auth.refreshSession();
      final user = Supabase.instance.client.auth.currentUser;

      if (!mounted) return;

      if (user == null) {
        _showSnack('Session expired. Please log in again.', error: true);
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      if (user.emailConfirmedAt == null) {
        _showSnack(
          'Your email is not yet verified. Please check your inbox '
          'and click the verification link.',
          error: true,
        );
        return;
      }

      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      debugPrint('VERIFY CHECK ERROR: $e');
      if (!mounted) return;
      _showSnack(
        'Could not check verification status. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _backToLogin() {
    if (_checking) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _openEmailApp() async {
    final uri = Uri(scheme: 'mailto');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('launchUrl failed: $e');
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.danger : AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final cooldown = _cooldownSeconds;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  // ── Hero icon ────────────────────────────────
                  Semantics(
                    label: 'Email verification required',
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.green.withValues(alpha: 0.25),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_rounded,
                        size: 44,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Title ────────────────────────────────────
                  const Text(
                    'Check your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'We sent a verification link to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Email (selectable) ───────────────────────
                  SelectableText(
                    widget.email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Instructions card ────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Verify your email address',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Open the verification email and tap the '
                          'verification link. Once completed, return '
                          'here and tap the button below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Primary: Continue to login ───────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _continueToLogin,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        _checking ? 'CHECKING…' : 'I’VE VERIFIED MY EMAIL',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── Secondary: Resend ────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: (_sending || !_canResend) ? null : _resend,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.green,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        disabledForegroundColor: AppColors.muted,
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _sending
                            ? 'SENDING…'
                            : cooldown > 0
                            ? 'RESEND IN ${cooldown}s'
                            : 'RESEND VERIFICATION EMAIL',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── Tertiary: Back to login ──────────────────
                  TextButton(
                    onPressed: _checking ? null : _backToLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Footer helper ────────────────────────────
                  const Text(
                    'Didn’t receive the email? Check your spam or junk folder.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ── Open email app ───────────────────────────
                  TextButton.icon(
                    onPressed: _openEmailApp,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.green,
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 12,
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text(
                      'Open email app',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
