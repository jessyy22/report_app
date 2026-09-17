import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import '../common/notifications_screen.dart';
import '../../widgets/notification_bell.dart';
import 'report_screen.dart';
import 'fare_calculator.dart';
import 'reports_view.dart';
import 'viganFareMatrix.dart';
import 'profile_view.dart';
import '../common/sos_screen.dart';

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

      if (role == 'driver') {
        final data = await supabase
            .from('driver_profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        name = data?['full_name']?.toString().trim();
      } else {
        final data = await supabase
            .from('commuter_profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        name = data?['full_name']?.toString().trim();
      }

      name ??= user.userMetadata?['full_name']?.toString().trim();

      if (mounted) {
        setState(() {
          _displayName = name != null && name.isNotEmpty ? name : 'there';
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

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the phone app.')),
      );
    }
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
      floatingActionButton: currentPageIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SOSScreen(userRole: 'commuter'),
                ),
              ),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.sos_rounded),
              label: const Text('SOS'),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.greenDark, AppColors.green],
              ),
              borderRadius: BorderRadius.circular(22),
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
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                      const SizedBox(height: 8),
                      const Text(
                        'Travel safer. Report responsibly.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const RTODASectionTitle(
            title: 'What do you need?',
            subtitle: 'Choose an action to get started.',
          ),
          const SizedBox(height: 12),
          RTODAActionCard(
            icon: Icons.edit_note_rounded,
            title: 'File a Report',
            subtitle: 'Report a tricycle incident or violation.',
            iconColor: Colors.red,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportForm()),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _compactAction(
                  Icons.calculate_rounded,
                  'Fare Calculator',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FareCalculatorScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _compactAction(
                  Icons.receipt_long_rounded,
                  'My Reports',
                  () => setState(() => currentPageIndex = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RTODAActionCard(
            icon: Icons.payments_rounded,
            title: 'Official Fare Guidelines',
            subtitle: 'View the current fare matrix and rules.',
            onTap: () => ViganFareMatrix.show(context),
          ),
          const SizedBox(height: 22),
          const RTODASectionTitle(title: 'Quick information'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withOpacity(.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF8A7200),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Use the official fare information before paying and keep your report details accurate.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text,
                        height: 1.35,
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

  Widget _compactAction(IconData icon, String label, VoidCallback onTap) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.green),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
