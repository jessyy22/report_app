import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import '../../widgets/notification_bell.dart';
import '../common/notifications_screen.dart';
import '../common/sos_screen.dart';
import 'fare_calculator.dart';
import 'profile_view.dart';
import 'report_screen.dart';
import 'reports_view.dart';
import 'viganFareMatrix.dart';

class NavigationBarApp extends StatelessWidget {
  const NavigationBarApp({super.key});

  @override
  Widget build(BuildContext context) => const Navigation();
}

class Navigation extends StatefulWidget {
  const Navigation({super.key});

  @override
  State<Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<Navigation> {
  int currentPageIndex = 0;
  String _displayName = 'there';
  bool _loadingName = true;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => _loadingName = false);
        return;
      }

      final role = user.userMetadata?['role']?.toString();
      String? name;
      String? photo;

      if (role == 'driver') {
        final data = await supabase
            .from('driver_profiles')
            .select('full_name, profile_photo_url')
            .eq('id', user.id)
            .maybeSingle();
        name = data?['full_name']?.toString().trim();
        photo = data?['profile_photo_url']?.toString().trim();
      } else {
        final data = await supabase
            .from('commuter_profiles')
            .select('full_name, profile_photo_url')
            .eq('id', user.id)
            .maybeSingle();
        name = data?['full_name']?.toString().trim();
        photo = data?['profile_photo_url']?.toString().trim();
      }

      name ??= user.userMetadata?['full_name']?.toString().trim();

      if (mounted) {
        setState(() {
          _displayName = name != null && name.isNotEmpty ? name : 'there';
          _photoUrl = (photo != null && photo.isNotEmpty) ? photo : null;
          _loadingName = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');

      final user = Supabase.instance.client.auth.currentUser;
      final fallback = user?.userMetadata?['full_name']?.toString().trim();

      if (mounted) {
        setState(() {
          _displayName = fallback != null && fallback.isNotEmpty
              ? fallback
              : 'there';
          _loadingName = false;
        });
      }
    }
  }

  // ── SOS navigation — call-only screen, no role needed ──────
  void _openSOSScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SOSScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHome(),
      const ReportView(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: currentPageIndex == 0
          ? AppBar(
              title: const Text('RTODA'),
              actions: const [NotificationBell()],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentPageIndex,
        onDestinationSelected: (index) =>
            setState(() => currentPageIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
      body: IndexedStack(index: currentPageIndex, children: pages),
    );
  }

  Widget _buildHome() {
    return RefreshIndicator(
      onRefresh: _loadUserName,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── Welcome banner ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.greenDark, AppColors.green],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome back',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      _loadingName
                          ? const SizedBox(
                              height: 28,
                              width: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      const SizedBox(height: 6),
                      const Text(
                        'Travel safer. Report responsibly.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _profileAvatar(),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const RTODASectionTitle(
            title: 'What do you need?',
            subtitle: 'Choose an action to get started.',
          ),
          const SizedBox(height: 12),

          // ── File a report ───────────────────────────────────
          RTODAActionCard(
            icon: Icons.edit_note_rounded,
            title: 'File a Report',
            subtitle: 'Report a tricycle incident or violation.',
            iconColor: AppColors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportForm()),
            ),
          ),
          const SizedBox(height: 12),

          // ── Compact actions row ─────────────────────────────
          Row(
            children: [
              Expanded(
                child: _compactAction(
                  Icons.calculate_rounded,
                  'Fare Calculator',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ViganFreeMapScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _compactAction(
                  Icons.receipt_long_rounded,
                  'My Reports',
                  () => setState(() => currentPageIndex = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Fare matrix ─────────────────────────────────────
          RTODAActionCard(
            icon: Icons.payments_rounded,
            title: 'Official Fare Guidelines',
            subtitle: 'View the current fare matrix and rules.',
            iconColor: AppColors.green,
            onTap: () => ViganFareMatrix.show(context),
          ),
          const SizedBox(height: 12),
          _sosButton(),

          const SizedBox(height: 24),

          const RTODASectionTitle(title: 'Quick information'),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.greenSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Use the official fare information before paying '
                      'and keep your report details accurate.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile avatar with graceful fallback ─────────────────
  Widget _profileAvatar() {
    if (_photoUrl == null || _photoUrl!.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.30),
            width: 1.5,
          ),
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        '$_photoUrl?t=${DateTime.now().millisecondsSinceEpoch}',
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.white.withValues(alpha: 0.15),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: Colors.white.withValues(alpha: 0.15),
          child: const Icon(
            Icons.person_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  // ── Emergency hotlines card ────────────────────────────────
  Widget _sosButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        onTap: _openSOSScreen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Hotlines',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Call PNP, fire, medical, or RTODA directly.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.danger,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactAction(IconData icon, String label, VoidCallback onTap) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.green),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
