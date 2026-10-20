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
  String? _idUrl;
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
          .from('commuter_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      String? signedId;
      final storedId = data?['id_photo_url']?.toString();

      if (storedId != null && storedId.isNotEmpty) {
        signedId = await _signedUrl(storedId);
      }

      if (!mounted) return;

      setState(() {
        _data = data;
        _idUrl = signedId;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ERROR FETCHING COMMUTER PROFILE: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your profile. Please try again.';
      });
    }
  }

  Future<String?> _signedUrl(String stored) async {
    try {
      var path = stored.trim();

      if (path.contains('/id-verifications/')) {
        path = path.split('/id-verifications/').last.split('?').first;
      }
      if (path.startsWith('id-verifications/')) {
        path = path.substring('id-verifications/'.length);
      }

      return await _supabase.storage
          .from('id-verifications')
          .createSignedUrl(path, 60 * 60); // 1 hour
    } catch (e) {
      debugPrint('ERROR CREATING ID SIGNED URL: $e');
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
      MaterialPageRoute(builder: (_) => EditProfileScreen(initialData: _data!)),
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
    final confirm = await showDialog<bool>(
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

    if (confirm != true || !mounted) return;

    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
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

  Future<void> _showFullId() async {
    final stored = _data?['id_photo_url']?.toString();
    if (stored == null || stored.isEmpty) return;

    final fresh = await _signedUrl(stored);
    if (fresh == null || !mounted) return;

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
                fresh,
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
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
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
        (data['full_name'] ?? user?.email?.split('@').first ?? 'Commuter')
            .toString();
    final phone = data['phone_number']?.toString().trim() ?? '';
    final photo = data['profile_photo_url']?.toString().trim() ?? '';
    final role = (data['role'] ?? 'commuter').toString().toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
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
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    // ── Header ────────────────────────────────
                    _headerCard(name, photo, role),
                    const SizedBox(height: 24),

                    // ── Account info ──────────────────────────
                    const RTODASectionTitle(title: 'Account information'),
                    const SizedBox(height: 12),
                    _infoItem(
                      Icons.email_outlined,
                      'Registered Email',
                      user?.email ?? 'Not available',
                    ),
                    _infoItem(
                      Icons.phone_outlined,
                      'Phone Number',
                      phone.isEmpty ? 'Not provided' : phone,
                    ),
                    if (data['address'] != null &&
                        data['address'].toString().trim().isNotEmpty)
                      _infoItem(
                        Icons.location_on_outlined,
                        'Address',
                        data['address'],
                      ),
                    const SizedBox(height: 24),

                    // ── Uploaded ID ───────────────────────────
                    const RTODASectionTitle(title: 'Uploaded ID'),
                    const SizedBox(height: 12),
                    _idCard(),
                    const SizedBox(height: 24),

                    // ── Account actions ───────────────────────
                    const RTODASectionTitle(title: 'Account'),
                    const SizedBox(height: 12),
                    _actionTile(
                      icon: Icons.edit_outlined,
                      label: 'Edit profile details',
                      subtitle: 'Update your name, phone, or photo',
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
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
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

  // ── Header card (avatar + name + role) ────────────────────────
  Widget _headerCard(String name, String photo, String role) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Tapping the avatar ALSO opens edit — but visually obvious
            // because of the pencil badge overlaid on it.
            Semantics(
              button: true,
              label: 'Change profile photo',
              child: GestureDetector(
                onTap: _edit,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    _profileAvatar(photo),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                role,
                style: const TextStyle(
                  color: AppColors.greenDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Avatar with graceful image handling ──────────────────────
  Widget _profileAvatar(String photo) {
    if (photo.isEmpty) {
      return const CircleAvatar(
        radius: 45,
        backgroundColor: AppColors.greenSoft,
        child: Icon(Icons.person_rounded, color: AppColors.green, size: 42),
      );
    }

    final url = '$photo?t=${DateTime.now().millisecondsSinceEpoch}';

    return CircleAvatar(
      radius: 45,
      backgroundColor: AppColors.greenSoft,
      child: ClipOval(
        child: Image.network(
          url,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, error, __) {
            debugPrint('PROFILE IMAGE ERROR: $error');
            return const Icon(
              Icons.person_rounded,
              color: AppColors.green,
              size: 42,
            );
          },
        ),
      ),
    );
  }

  // ── Info item (read-only field) ───────────────────────────────
  Widget _infoItem(IconData icon, String label, dynamic value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _iconBox(icon),
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

  // ── Action tile (tap to navigate) ─────────────────────────────
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
            color: destructive ? AppColors.dangerSoft : AppColors.greenSoft,
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
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
          size: 20,
        ),
      ),
    );
  }

  // ── Icon box (matches info items) ─────────────────────────────
  Widget _iconBox(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: AppColors.green, size: 20),
    );
  }

  // ── ID card ───────────────────────────────────────────────────
  Widget _idCard() {
    if (_idUrl == null || _idUrl!.isEmpty) {
      return Card(
        child: Container(
          height: 170,
          alignment: Alignment.center,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.badge_outlined, size: 45, color: AppColors.muted),
              SizedBox(height: 8),
              Text(
                'ID image unavailable',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showFullId,
        child: Column(
          children: [
            Image.network(
              _idUrl!,
              height: 210,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  height: 210,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (_, error, __) {
                debugPrint('ID IMAGE ERROR: $error');
                return Container(
                  height: 160,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(20),
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
                        'Unable to display ID',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.zoom_in, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Tap to view ID',
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
}
