import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

class AccountStatusScreen extends StatefulWidget {
  final String status;
  final String? rejectionReason;
  final Future<void> Function()? onRefresh;

  const AccountStatusScreen({
    super.key,
    required this.status,
    this.rejectionReason,
    this.onRefresh,
  });

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  bool _checking = false;

  // ============================================================
  // STATUS CONFIG
  // ============================================================
  _StatusConfig get _config {
    final normalized = widget.status.toLowerCase();
    final reason = widget.rejectionReason?.trim();

    switch (normalized) {
      case 'approved':
      case 'active':
        return _StatusConfig(
          icon: Icons.verified_rounded,
          color: AppColors.green,
          title: 'Account Approved',
          message: 'Your RTODA account is ready to use.',
          canRefresh: true,
          showSupport: false,
        );
      case 'rejected':
        return _StatusConfig(
          icon: Icons.cancel_rounded,
          color: AppColors.danger,
          title: 'Application Rejected',
          message: reason != null && reason.isNotEmpty
              ? reason
              : 'Your driver application was not approved. Please '
                    'contact RTODA / LGU for more information.',
          canRefresh: true,
          showSupport: true,
        );
      case 'suspended':
        return _StatusConfig(
          icon: Icons.block_rounded,
          color: Colors.orange.shade800,
          title: 'Account Suspended',
          message:
              'Your account is currently suspended. Please '
              'contact RTODA / LGU for assistance.',
          canRefresh: true,
          showSupport: true,
        );
      default:
        return _StatusConfig(
          icon: Icons.hourglass_top_rounded,
          color: Colors.amber.shade800,
          title: 'Waiting for Verification',
          message:
              'Your driver application is being reviewed by an '
              'authorized RTODA / LGU administrator.',
          canRefresh: true,
          showSupport: false,
        );
    }
  }

  // ============================================================
  // ACTIONS
  // ============================================================
  Future<void> _checkStatus() async {
    if (_checking || widget.onRefresh == null) return;

    setState(() => _checking = true);
    try {
      await widget.onRefresh!.call();
    } catch (e) {
      debugPrint('STATUS REFRESH ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not refresh status: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri(scheme: 'tel', path: '09171032784');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('launchUrl failed: $e');
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contact RTODA'),
        content: const SelectableText(
          '0917-103-2784',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _backToLogin() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final cfg = _config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Status'),
        // No actions; back button appears automatically if pushed.
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  // ── Status icon ─────────────────────────────
                  Semantics(
                    label: cfg.title,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: cfg.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: cfg.color.withValues(alpha: 0.25),
                          width: 2,
                        ),
                      ),
                      child: Icon(cfg.icon, size: 48, color: cfg.color),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Title ───────────────────────────────────
                  Text(
                    cfg.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Status pill ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      widget.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cfg.color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Message card ────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      cfg.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Primary action ──────────────────────────
                  if (cfg.canRefresh && widget.onRefresh != null)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _checking ? null : _checkStatus,
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
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(
                          _checking ? 'CHECKING…' : 'CHECK STATUS AGAIN',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                  // ── Secondary action (rejected/suspended) ───
                  if (cfg.showSupport) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _contactSupport,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.green,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.support_agent_rounded, size: 20),
                        label: const Text(
                          'CONTACT SUPPORT',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Back to login ───────────────────────────
                  TextButton(
                    onPressed: _backToLogin,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Status config holder
// ============================================================
class _StatusConfig {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final bool canRefresh;
  final bool showSupport;

  const _StatusConfig({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.canRefresh,
    required this.showSupport,
  });
}
