import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import '../common/notifications_screen.dart';
import '../common/sos_screen.dart';
import 'driver_report_page.dart';
import 'profile_screen.dart';
import 'viganFareMatrix.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;

  String _driverName = 'Driver';
  String _bodyNumber = 'N/A';
  String _status = 'Checking...';
  String _rating = '5.0';

  int _activeReports = 0;

  String? _photoUrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchDriverProfile();
  }

  Future<void> _fetchDriverProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please log in to open the driver dashboard.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _supabase
          .from('driver_profiles')
          .select(
            'id,full_name,body_number,rating,is_active,'
            'profile_photo_url,phone_number,verification_status',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage =
              'No driver profile was found for this account.\n\n'
              'UID: ${user.id}';
        });
        return;
      }

      final body = (data['body_number'] ?? '').toString().trim();
      int openReports = 0;

      if (body.isNotEmpty) {
        try {
          final response = await _supabase
              .from('reports')
              .select('report_id,status')
              .eq('body_number', body);

          final reports = List<Map<String, dynamic>>.from(response);

          openReports = reports.where((report) {
            final status = (report['status'] ?? '').toString().toLowerCase();
            return status != 'resolved' && status != 'dismissed';
          }).length;
        } catch (e) {
          debugPrint('REPORT QUERY ERROR: $e');
        }
      }

      final profileName = data['full_name']?.toString().trim();
      final authName = user.userMetadata?['full_name']?.toString().trim();
      final photo = data['profile_photo_url']?.toString().trim();

      if (!mounted) return;

      setState(() {
        _driverName = profileName?.isNotEmpty == true
            ? profileName!
            : authName?.isNotEmpty == true
            ? authName!
            : 'Driver';
        _bodyNumber = body.isEmpty ? 'N/A' : body;
        _rating = (data['rating'] ?? '5.0').toString();
        _status = data['is_active'] == true ? 'Active' : 'Inactive';
        _activeReports = openReports;
        _photoUrl = photo?.isNotEmpty == true ? photo : null;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('DRIVER PROFILE ERROR: $error');
      debugPrint('STACK TRACE: $stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load driver information.\n\n$error';
      });
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Portal'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: _openProfile,
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _fetchDriverProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 64,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: FilledButton.icon(
                onPressed: _fetchDriverProfile,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDriverProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          _profileHero(),
          const SizedBox(height: 16),
          _statusCard(),
          const SizedBox(height: 16),
          _sosButton(),
          const SizedBox(height: 22),
          const RTODASectionTitle(
            title: 'Quick actions',
            subtitle: 'Access your reports and the official fare information.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _action(
                  Icons.assignment_rounded,
                  'My Reports',
                  _openReports,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _action(
                  Icons.payments_rounded,
                  'Fare Matrix',
                  () => ViganFareMatrix.show(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const RTODASectionTitle(title: 'Driver reminder'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.greenSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.fact_check_rounded,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Review your reports regularly and submit an '
                      'explanation when the LGU requests a response.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textSecondary,
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

  Widget _profileHero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.greenDark, AppColors.green],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: _photoUrl == null || _photoUrl!.isEmpty
                ? const Icon(
                    Icons.person_rounded,
                    color: AppColors.green,
                    size: 34,
                  )
                : Image.network(
                    _photoUrl!,
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.person_rounded,
                      color: AppColors.green,
                      size: 34,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()},',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  _driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _bodyNumber == 'N/A'
                        ? AppColors.dangerSoft
                        : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    _bodyNumber == 'N/A'
                        ? 'NO BODY NUMBER'
                        : 'BODY NO. $_bodyNumber',
                    style: TextStyle(
                      color: _bodyNumber == 'N/A'
                          ? AppColors.danger
                          : AppColors.greenDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final clear = _activeReports == 0;
    final active = _status.toLowerCase() == 'active';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: active ? AppColors.green : Colors.orange.shade800,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Operational status',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _status,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: active ? AppColors.green : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    Icons.warning_amber_rounded,
                    'Open reports',
                    _activeReports.toString(),
                  ),
                ),
                Expanded(child: _metric(Icons.star_rounded, 'Rating', _rating)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statusPill(
                    label: 'Account',
                    value: _status,
                    color: active ? AppColors.green : Colors.orange.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statusPill(
                    label: 'Reports',
                    value: clear ? 'Clear' : 'Has open',
                    color: clear ? AppColors.green : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: ',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── SOS card — navigates to SOSScreen ─────────────────────
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
                      'SOS Emergency Alert',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Open the emergency screen to alert RTODA '
                      'administrators.',
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

  void _openSOSScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SOSScreen(
          userRole: 'driver',
          bodyNumber: _bodyNumber == 'N/A' ? null : _bodyNumber,
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.greenSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.green, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, String title, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: title,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: AppColors.green),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );

    if (!mounted) return;
    if (result == true) {
      await _fetchDriverProfile();
    }
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverReportsPage(bodyNumber: _bodyNumber),
      ),
    );
  }
}
