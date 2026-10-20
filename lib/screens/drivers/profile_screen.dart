import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _data;
  String? _licenseUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  // ============================================================
  // DATA
  // ============================================================
  Future<void> _fetch() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'You are not signed in.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _supabase
          .from('driver_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      String? signed;
      final stored = data?['license_photo_url']?.toString();

      if (stored != null && stored.isNotEmpty) {
        signed = await _resolveLicenseUrl(stored);
      }

      if (!mounted) return;
      setState(() {
        _data = data;
        _licenseUrl = signed;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching driver profile: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your profile. Please try again.';
      });
    }
  }

  /// Resolves a license URL: if the bucket is private, generate a signed
  /// URL; if it's public, just use the URL as-is.
  Future<String?> _resolveLicenseUrl(String stored) async {
    try {
      // Already a public URL? Return directly.
      if (stored.startsWith('http') && !stored.contains('/object/sign/')) {
        // Public bucket — no signing needed
        return stored;
      }

      // Detect bucket from URL path
      String bucket = 'license-photos';
      String path = stored;

      for (final b in [
        'license-photos',
        'id-verifications',
        'driver-avatars',
      ]) {
        if (stored.contains('/$b/')) {
          bucket = b;
          path = stored.split('/$b/').last.split('?').first;
          break;
        }
      }

      return await _supabase.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60); // 1 hour
    } catch (e) {
      debugPrint('Error creating signed URL: $e');
      return null;
    }
  }

  // ============================================================
  // NAVIGATION
  // ============================================================
  Future<void> _edit() async {
    if (_data == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(initialData: _data!),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      await _fetch();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated successfully.'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.logout_rounded,
          color: AppColors.danger,
          size: 40,
        ),
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to log in again to access your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to sign out: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showFullLicense() async {
    if (_licenseUrl == null) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                _licenseUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final data = _data ?? {};
    final name =
        (data['full_name'] ?? user?.email?.split('@').first ?? 'Driver')
            .toString();
    final photo =
        (data['profile_photo_url'] ?? data['avatar_url'] ?? '').toString();
    final bodyNumber = (data['body_number'] ?? '').toString();
    final hasBodyNumber =
        bodyNumber.isNotEmpty && bodyNumber.toUpperCase() != 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        // Single edit entry point — nothing else.
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            onPressed: _edit,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState()
                : RefreshIndicator(
                    onRefresh: _fetch,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                      children: [
                        _headerCard(
                          name: name,
                          photo: photo,
                          bodyNumber: hasBodyNumber
                              ? bodyNumber
                              : null,
                        ),
                        const SizedBox(height: 24),

                        const RTODASectionTitle(
                          title: 'Driver information',
                        ),
                        const SizedBox(height: 12),
                        _infoItem(
                          Icons.badge_outlined,
                          'License Number',
                          data['license_number'] ?? 'Not provided',
                        ),
                        _infoItem(
                          Icons.email_outlined,
                          'Registered Email',
                          user?.email ?? 'Not available',
                        ),
                        _infoItem(
                          Icons.phone_outlined,
                          'Phone Number',
                          data['phone_number'] ?? 'Not provided',
                        ),
                        _infoItem(
                          Icons.star_rounded,
                          'Rating',
                          '${data['rating'] ?? '5.0'} / 5.0',
                        ),
                        const SizedBox(height: 24),

                        if (_licenseUrl != null) ...[
                          const RTODASectionTitle(
                            title: 'Submitted license',
                          ),
                          const SizedBox(height: 12),
                          _licenseCard(),
                          const SizedBox(height: 24),
                        ],

                        const RTODASectionTitle(title: 'Account'),
                        const SizedBox(height: 12),
                        _actionTile(
                          icon: Icons.edit_outlined,
                          label: 'Edit profile details',
                          subtitle:
                              'Update your name, license, or photo',
                          onTap: _edit,
                        ),
                        const SizedBox(height: 8),
                        _actionTile(
                          icon: Icons.logout_rounded,
                          label: 'Sign out',
                          subtitle: 'Log out of this device',
                          onTap: _signOut,
                          destructive: true,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ============================================================
  // SUB-WIDGETS
  // ============================================================

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard({
    required String name,
    required String photo,
    required String? bodyNumber,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Semantics(
              button: true,
              label: 'Change profile photo',
              child: GestureDetector(
                onTap: _edit,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.greenSoft,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: photo.isNotEmpty
                          ? Image.network(
                              '$photo?t=${DateTime.now().millisecondsSinceEpoch}',
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person_rounded,
                                color: AppColors.green,
                                size: 42,
                              ),
                            )
                          : const Icon(
                              Icons.person_rounded,
                              color: AppColors.green,
                              size: 42,
                            ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: bodyNumber == null
                    ? AppColors.dangerSoft
                    : AppColors.greenSoft,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                bodyNumber == null
                    ? 'NO BODY NUMBER'
                    : 'BODY NO. $bodyNumber',
                style: TextStyle(
                  color: bodyNumber == null
                      ? AppColors.danger
                      : AppColors.greenDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licenseCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showFullLicense,
        child: Column(
          children: [
            Image.network(
              _licenseUrl!,
              height: 210,
              width: double.infinity,
              fit: BoxFit.cover,
              semanticLabel: 'Submitted driver license',
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  height: 210,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                alignment: Alignment.center,
                color: AppColors.background,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 40,
                      color: AppColors.muted,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'License image unavailable.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.zoom_in, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Tap to view license',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, dynamic value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.greenSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.green, size: 20),
        ),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          value?.toString() ?? 'Not provided',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? AppColors.danger : AppColors.green;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: destructive
                ? AppColors.dangerSoft
                : AppColors.greenSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: destructive ? AppColors.danger : AppColors.text,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.muted,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
          size: 20,
        ),
      ),
    );
  }
}