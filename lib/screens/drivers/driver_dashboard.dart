import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import '../common/notifications_screen.dart';
import 'driver_report_page.dart';
import 'profile_screen.dart';
import 'viganFareMatrix.dart';
import '../../services/notification_service.dart';

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
      debugPrint('AUTH USER ID: ${user.id}');

      final data = await _supabase
          .from('driver_profiles')
          .select(
            'id,full_name,body_number,rating,is_active,'
            'profile_photo_url,phone_number,verification_status',
          )
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('DRIVER PROFILE DATA: $data');

      if (data == null) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
          _errorMessage =
              'No driver profile was found for this account.\n\nUID: ${user.id}';
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
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 110),
            const Icon(Icons.person_off_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                      'Review your reports regularly and submit an explanation when the LGU requests a response.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.text,
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
    final image = _photoUrl == null ? null : NetworkImage(_photoUrl!);

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
          CircleAvatar(
            radius: 31,
            backgroundColor: Colors.white,
            backgroundImage: image,
            child: image == null
                ? const Icon(
                    Icons.person_rounded,
                    color: AppColors.green,
                    size: 34,
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Good day,',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    'BODY NO. $_bodyNumber',
                    style: const TextStyle(
                      color: AppColors.greenDark,
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
                    color: active ? Colors.green : Colors.orange,
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
                    color: active ? Colors.green : Colors.orange,
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
            Align(
              alignment: Alignment.centerLeft,
              child: RTODAStatusBadge(
                status: clear ? 'Clear' : 'Under Investigation',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sosButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: InkWell(
        onTap: _showSOSConfirmation,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.red,
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
                        color: Colors.red,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Send an emergency alert to RTODA administrators.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.red,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSOSConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Send SOS Alert?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'An emergency alert will be sent to RTODA administrators using your driver account and body number.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sendSOS();
    }
  }

  Future<void> _sendSOS() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    if (_bodyNumber == 'N/A' || _bodyNumber.trim().isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your driver information is not available. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    try {
      await _supabase.from('sos_alerts').insert({
        'user_id': user.id,
        'body_number': _bodyNumber,
        'status': 'active',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      try {
        await NotificationService.sendPushToRole(
          role: 'admin',
          title: 'Driver SOS Alert',
          message: 'Driver $_bodyNumber has sent an emergency SOS alert.',
          type: 'sos',
        );
      } catch (e) {
        debugPrint('Admin SOS notification error: $e');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert sent to RTODA administrators.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('SOS ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to send SOS alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
    return Card(
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
    );
  }

  Future<void> _openProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );

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
