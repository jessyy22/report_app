import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import 'report_details.dart';

class ReportView extends StatefulWidget {
  const ReportView({super.key});

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _reports = <Map<String, dynamic>>[];
  bool _isLoading = true;
  String? _errorMessage;
  String _filter = 'All';

  static const List<String> _filters = <String>[
    'All',
    'Pending',
    'Under Review',
    'Under Investigation',
    'Summoned',
    'Resolved',
    'Dismissed',
  ];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _reports = <Map<String, dynamic>>[];
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('reports')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(response as List);

      if (!mounted) return;
      setState(() {
        _reports = rows;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Error loading commuter reports: $error');
      if (!mounted) return;
      setState(() {
        _reports = <Map<String, dynamic>>[];
        _isLoading = false;
        _errorMessage = 'Unable to load your reports. Please try again.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredReports {
    if (_filter == 'All') return _reports;

    return _reports.where((report) {
      final status = (report['status'] ?? 'Pending').toString().trim();
      return status.toLowerCase() == _filter.toLowerCase();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: user == null
          ? _emptyState(
              Icons.lock_outline_rounded,
              'Please log in',
              'Log in to view the reports you have submitted.',
            )
          : RefreshIndicator(onRefresh: _loadReports, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _reports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _reports.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          _emptyState(
            Icons.cloud_off_rounded,
            'Unable to load reports',
            _errorMessage!,
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: _loadReports,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ),
        ],
      );
    }

    final reports = _filteredReports;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const RTODASectionTitle(
          title: 'Track your reports',
          subtitle: 'View the latest status and details of your submissions.',
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filters.map((filter) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  onSelected: (selected) {
                    if (selected) setState(() => _filter = filter);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (reports.isEmpty)
          _emptyState(
            Icons.assignment_turned_in_outlined,
            _filter == 'All' ? 'No reports yet' : 'No $_filter reports',
            _filter == 'All'
                ? 'Reports you submit will appear here.'
                : 'Try another status filter.',
          )
        else
          ...reports.map(_buildReportCard),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = (report['status'] ?? 'Pending').toString();
    final reportId = (report['report_id'] ?? 'N/A').toString();
    final violation = (report['violation'] ?? 'Unspecified violation')
        .toString();
    final bodyNumber = (report['body_number'] ?? 'N/A').toString();
    final location = (report['location'] ?? 'Location not provided').toString();
    final date = (report['incidentdate'] ?? report['created_at'] ?? '')
        .toString();
    final evidence = (report['evidence_url'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportDetailsScreen(report: report),
            ),
          );
          _loadReports();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '#$reportId',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RTODAStatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                violation,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _meta(Icons.directions_car_rounded, 'Body No. $bodyNumber'),
              const SizedBox(height: 5),
              _meta(Icons.location_on_outlined, location),
              const SizedBox(height: 5),
              _meta(Icons.calendar_today_outlined, _formatDate(date)),
              const Divider(height: 22),
              Row(
                children: [
                  if (evidence.isNotEmpty) ...[
                    const Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Evidence attached',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Text(
                    'View details',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String value) {
    if (value.isEmpty) return 'Date not available';
    if (value.contains('T')) return value.split('T').first;
    return value;
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.greenSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.green),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
