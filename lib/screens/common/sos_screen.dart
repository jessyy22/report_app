import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

// ============================================================================
// Emergency contact model
// ============================================================================
class EmergencyContact {
  final String label;
  final String phone;
  final IconData icon;
  final Color color;

  const EmergencyContact({
    required this.label,
    required this.phone,
    required this.icon,
    required this.color,
  });
}

const List<EmergencyContact> _defaultContacts = [
  EmergencyContact(
    label: '911',
    phone: '911',
    icon: Icons.emergency,
    color: AppColors.danger,
  ),
  EmergencyContact(
    label: 'PNP Vigan',
    phone: '09178607316', // ← VERIFY
    icon: Icons.local_police,
    color: Color(0xFF1D4ED8),
  ),
  EmergencyContact(
    label: 'Fire',
    phone: '09171873911', // ← VERIFY
    icon: Icons.local_fire_department,
    color: Color(0xFFC2410C),
  ),
  EmergencyContact(
    label: 'Medical',
    phone: '09171032784', // ← VERIFY
    icon: Icons.local_hospital,
    color: AppColors.danger,
  ),
  EmergencyContact(
    label: 'PSTMO',
    phone: '09171032784',
    icon: Icons.electric_rickshaw,
    color: AppColors.green,
  ),
];

// ============================================================================
// SOS screen — emergency call only
// ============================================================================
class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  List<EmergencyContact> _contacts = _defaultContacts;
  bool _loadingContacts = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  // ============================================================
  // EMERGENCY CONTACTS (optional — falls back to defaults)
  // ============================================================
  Future<void> _loadContacts() async {
    try {
      final rows = await Supabase.instance.client
          .from('emergency_contacts')
          .select('label, phone, category')
          .eq('active', true)
          .order('sort_order');

      if (!mounted) return;

      if (rows.isNotEmpty) {
        setState(() {
          _contacts = rows
              .map((r) {
                final cat = (r['category'] ?? 'other').toString();
                return EmergencyContact(
                  label: r['label'].toString(),
                  phone: r['phone'].toString(),
                  icon: _iconForCategory(cat),
                  color: _colorForCategory(cat),
                );
              })
              .toList(growable: false);
          _loadingContacts = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Emergency contacts load failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _contacts = _defaultContacts;
      _loadingContacts = false;
    });
  }

  IconData _iconForCategory(String c) {
    switch (c) {
      case 'police':
        return Icons.local_police;
      case 'fire':
        return Icons.local_fire_department;
      case 'medical':
        return Icons.local_hospital;
      case 'rtoda':
        return Icons.electric_rickshaw;
      case 'national':
        return Icons.emergency;
      default:
        return Icons.phone;
    }
  }

  Color _colorForCategory(String c) {
    switch (c) {
      case 'police':
        return const Color(0xFF1D4ED8);
      case 'fire':
        return const Color(0xFFC2410C);
      case 'medical':
        return AppColors.danger;
      case 'rtoda':
        return AppColors.green;
      case 'national':
        return AppColors.danger;
      default:
        return AppColors.muted;
    }
  }

  // ============================================================
  // DIALER
  // ============================================================
  Future<void> _callNumber(String rawNumber, String label) async {
    final clean = rawNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) {
      _showSnack('Invalid phone number.', color: AppColors.danger);
      return;
    }

    final uri = Uri(scheme: 'tel', path: clean);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('launchUrl failed: $e');
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Call $label'),
        content: SelectableText(
          rawNumber,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: clean));
              if (ctx.mounted) Navigator.pop(ctx);
              _showSnack('Number copied', color: AppColors.green);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('COPY'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Hotlines')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 911 banner ──────────────────────────────────────
              _fallbackBanner(),

              const SizedBox(height: 24),

              // ── Hero icon ───────────────────────────────────────
              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.sos_rounded,
                    color: AppColors.danger,
                    size: 60,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Emergency Hotlines',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap a contact below to call directly. Use these only in '
                'genuine emergencies.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              // ── Contact list ────────────────────────────────────
              if (_loadingContacts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                ..._contacts.map(_contactTile),

              const SizedBox(height: 24),

              // ── Info ────────────────────────────────────────────
              _infoCard(theme),
            ],
          ),
        ),
      ),
    );
  }

  // ── 911 banner ──────────────────────────────────────────────
  Widget _fallbackBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_in_talk, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Life-threatening emergency? Call 911 directly.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _callNumber('911', '911'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'CALL',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Contact tile ────────────────────────────────────────────
  Widget _contactTile(EmergencyContact c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.color.withValues(alpha: 0.25)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(c.icon, color: c.color, size: 22),
          ),
          title: Text(
            c.label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          subtitle: Text(
            c.phone,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: Icon(Icons.call, color: c.color),
          onTap: () => _callNumber(c.phone, c.label),
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: c.phone));
            _showSnack('Copied ${c.phone}', color: AppColors.green);
          },
        ),
      ),
    );
  }

  Widget _infoCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.green,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Calls open your phone dialer. Your number is not shared with '
              'the RTODA monitoring team automatically — this screen only '
              'helps you reach the right hotline fast.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
