import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../services/sos_service.dart';

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
    phone: '0998-598-5555', // ← VERIFY
    icon: Icons.local_police,
    color: Color(0xFF1D4ED8),
  ),
  EmergencyContact(
    label: 'Fire',
    phone: '0917-000-0000', // ← VERIFY
    icon: Icons.local_fire_department,
    color: Color(0xFFC2410C),
  ),
  EmergencyContact(
    label: 'Medical',
    phone: '0917-000-0000', // ← VERIFY
    icon: Icons.local_hospital,
    color: AppColors.danger,
  ),
  EmergencyContact(
    label: 'RTODA',
    phone: '0917-103-2784',
    icon: Icons.electric_rickshaw,
    color: AppColors.green,
  ),
];

// ============================================================================
// SOS screen
// ============================================================================
class SOSScreen extends StatefulWidget {
  final String userRole;
  final String? bodyNumber; // ← new optional parameter

  const SOSScreen({super.key, required this.userRole, this.bodyNumber});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  final _descriptionController = TextEditingController();

  bool _sending = false;
  bool _sent = false;

  List<EmergencyContact> _contacts = _defaultContacts;
  bool _loadingContacts = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // ============================================================
  // EMERGENCY CONTACTS
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
  // LOCATION
  // ============================================================
  Future<Position> _getLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Please turn on your device location.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
        'Please enable it in your device settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw Exception(
        'Could not acquire GPS in time. Move to an open area and try '
        'again, or call emergency services directly.',
      );
    }
  }

  Future<String?> _getLocationName(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;

      final parts =
          [p.street, p.subLocality, p.locality, p.administrativeArea, p.country]
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      return parts.isEmpty ? null : parts.join(', ');
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');
      return null;
    }
  }

  // ============================================================
  // SEND SOS
  // ============================================================
  Future<void> _confirmSOS() async {
    if (_sending) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(
            Icons.warning_rounded,
            color: AppColors.danger,
            size: 40,
          ),
          title: const Text('Send SOS Alert?'),
          content: const Text(
            'This will send an emergency alert to the RTODA monitoring '
            'team and share your current location.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SEND SOS'),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      await _sendSOS();
    }
  }

  Future<void> _sendSOS() async {
    if (_sending) return;

    setState(() => _sending = true);

    try {
      final position = await _getLocation();
      debugPrint('SOS GPS: ${position.latitude}, ${position.longitude}');

      final locationName = await _getLocationName(position);
      debugPrint('SOS Location Name: $locationName');

      await SOSService.sendSOS(
        userRole: widget.userRole,
        latitude: position.latitude,
        longitude: position.longitude,
        locationName: locationName,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        driverBodyNumber: widget.bodyNumber, // ← pass through
      );

      if (!mounted) return;

      HapticFeedback.heavyImpact();

      setState(() {
        _sending = false;
        _sent = true;
      });

      _showSnack(
        'SOS alert sent. The RTODA monitoring team has been notified.',
        color: AppColors.green,
        action: SnackBarAction(
          label: 'NEW SOS',
          onPressed: () => setState(() => _sent = false),
        ),
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _sending = false);

      _showSnack(
        'Failed to send SOS: $e',
        color: AppColors.danger,
        action: SnackBarAction(label: 'RETRY', onPressed: _sendSOS),
        duration: const Duration(seconds: 10),
      );
    }
  }

  void _showSnack(
    String message, {
    required Color color,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          action: action,
          duration: duration,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSent = _sent;
    final accent = isSent ? AppColors.green : AppColors.danger;

    return PopScope(
      canPop: !_sending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _showSnack(
            'Sending SOS — please wait…',
            color: Colors.orange.shade800,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('SOS Alert')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 911 fallback banner ─────────────────────────────
                _fallbackBanner(),

                const SizedBox(height: 24),

                // ── Hero SOS icon ───────────────────────────────────
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      isSent ? Icons.check_circle_rounded : Icons.sos_rounded,
                      color: accent,
                      size: 60,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Title + subtitle ────────────────────────────────
                Text(
                  isSent ? 'Alert Sent' : 'Emergency SOS',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isSent
                      ? 'Your SOS alert has been sent. The RTODA monitoring '
                            'team has been notified.'
                      : 'Use this button only when you need urgent assistance '
                            'from the RTODA monitoring team.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Description ─────────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: isSent
                      ? const SizedBox(width: double.infinity)
                      : TextField(
                          controller: _descriptionController,
                          enabled: !_sending,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'What happened? (Optional)',
                            hintText: 'Briefly describe the emergency…',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 24),

                // ── SOS button ──────────────────────────────────────
                _sosButton(accent, isSent),

                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _sending
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Locating you and contacting the RTODA team…',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 24),

                // ── Emergency contacts ──────────────────────────────
                _emergencyContactsCard(theme),

                const SizedBox(height: 16),

                // ── Info ────────────────────────────────────────────
                _infoCard(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 911 fallback banner ──────────────────────────────────────
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

  // ── SOS button ───────────────────────────────────────────────
  Widget _sosButton(Color accent, bool isSent) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Semantics(
        button: true,
        label: isSent ? 'SOS alert already sent' : 'Send SOS emergency alert',
        child: ElevatedButton.icon(
          onPressed: _sending || _sent ? null : _confirmSOS,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _sent
                ? AppColors.green
                : Colors.grey.shade400,
            disabledForegroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  _sent ? Icons.check_circle_rounded : Icons.sos_rounded,
                  size: 22,
                ),
          label: Text(
            _sending
                ? 'SENDING SOS…'
                : _sent
                ? 'SOS SENT'
                : 'SEND SOS ALERT',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  // ── Emergency contacts card ──────────────────────────────────
  Widget _emergencyContactsCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.phone_in_talk,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Emergency Contacts',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _loadingContacts ? 'Loading…' : 'Tap to call',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingContacts)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _contacts
                  .map((c) => _contactChip(c))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _contactChip(EmergencyContact c) {
    return Material(
      color: c.color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _callNumber(c.phone, c.label),
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: c.phone));
          _showSnack('Copied ${c.phone}', color: AppColors.green);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(c.icon, size: 16, color: c.color),
              const SizedBox(width: 6),
              Text(
                c.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
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
              'Your current GPS location will be included with the SOS alert. '
              'If GPS is unavailable, the last known location will be used.',
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
