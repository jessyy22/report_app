import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class DriverReportsPage extends StatefulWidget {
  final String bodyNumber;

  const DriverReportsPage({super.key, required this.bodyNumber});

  @override
  State<DriverReportsPage> createState() => _DriverReportsPageState();
}

class _DriverReportsPageState extends State<DriverReportsPage> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _fetchDriverReports();
  }

  // ============================================================
  // DATA
  // ============================================================
  Future<void> _fetchDriverReports() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('reports')
          .select(
            'report_id, violation, report_type, location, '
            'latitude, longitude, status, '
            'incidentdate, incidenttime, created_at, '
            'evidence_url, driver_feedback, description',
          )
          .eq('body_number', widget.bodyNumber)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _reports = List<Map<String, dynamic>>.from(data ?? []);
      });
    } catch (e) {
      debugPrint('DRIVER REPORTS ERROR: $e');
      if (!mounted) return;
      _showSnack('Could not load reports: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitFeedback(String reportId, String feedback) async {
    await supabase
        .from('reports')
        .update({'driver_feedback': feedback})
        .eq('report_id', reportId);
  }

  // ============================================================
  // HELPERS
  // ============================================================
  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.danger : AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return AppColors.green;
      case 'under review':
      case 'summoned':
        return Colors.blue.shade700;
      case 'dismissed':
        return AppColors.muted;
      default:
        return Colors.orange.shade800;
    }
  }

  bool _isResolved(String status) =>
      status.toLowerCase() == 'resolved';

  // Prefer the modern `report_type`, fall back to legacy `violation`.
  String _reportTitle(Map<String, dynamic> r) {
    final modern = (r['report_type'] ?? '').toString().trim();
    if (modern.isNotEmpty) return modern;
    final legacy = (r['violation'] ?? '').toString().trim();
    if (legacy.isNotEmpty) return legacy;
    return 'Unspecified Incident';
  }

  // Prefer `location`, fall back to coordinates.
  String _reportLocation(Map<String, dynamic> r) {
    final text = (r['location'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;
    final lat = r['latitude'];
    final lng = r['longitude'];
    if (lat is num && lng is num) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    return 'Unknown Location';
  }

  // Combine `incidentdate` + `incidenttime`, fall back to `created_at`.
  String _reportDate(Map<String, dynamic> r) {
    final date = r['incidentdate']?.toString();
    final time = r['incidenttime']?.toString();

    if (date != null && date.isNotEmpty) {
      final combined = time != null && time.isNotEmpty
          ? '$date $time'
          : date;
      final parsed = DateTime.tryParse(combined);
      if (parsed != null) {
        return DateFormat('MMM d, y • hh:mm a').format(parsed.toLocal());
      }
      return combined;
    }

    final created = r['created_at']?.toString();
    if (created != null && created.isNotEmpty) {
      final parsed = DateTime.tryParse(created);
      if (parsed != null) {
        return DateFormat('MMM d, y • hh:mm a').format(parsed.toLocal());
      }
    }
    return 'Unknown date';
  }

  String? _reportDescription(Map<String, dynamic> r) {
    final d = (r['description'] ?? '').toString().trim();
    return d.isEmpty ? null : d;
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Report History')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchDriverReports,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _reports.length,
                      itemBuilder: (context, i) =>
                          _buildReportCard(_reports[i]),
                    ),
        ),
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────────
  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Semantics(
          label:
              'All clear. No complaints have been filed against your body number.',
          child: Column(
            children: [
              Icon(
                Icons.assignment_turned_in_rounded,
                size: 72,
                color: AppColors.green.withValues(alpha: 0.30),
              ),
              const SizedBox(height: 16),
              const Text(
                'All Clear',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'No commuter complaints have been filed against '
                'your body number.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Report card ─────────────────────────────────────────────
  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = (report['status'] ?? 'Pending').toString();
    final explanation = (report['driver_feedback'] ?? '').toString();
    final hasResponded = explanation.trim().isNotEmpty;
    final isResolved = _isResolved(status);
    final statusColor = _statusColor(status);
    final reportId = report['report_id']?.toString() ?? '';
    final evidenceUrl = (report['evidence_url'] ?? '').toString();
    final description = _reportDescription(report);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _reportTitle(report),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Location ───────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 14,
                color: AppColors.muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _reportLocation(report),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // ── Date ───────────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: AppColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                _reportDate(report),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),

          // ── Commuter description ───────────────────────────
          if (description != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Complainant’s description',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Evidence ───────────────────────────────────────
          if (evidenceUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _openEvidence(evidenceUrl),
                child: Image.network(
                  evidenceUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  semanticLabel: 'Evidence photo for this report',
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 140,
                      color: AppColors.borderLight,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    height: 140,
                    color: AppColors.borderLight,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          const Divider(height: 24, color: AppColors.border),

          // ── Explanation ────────────────────────────────────
          if (hasResponded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: AppColors.greenDark,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Your explanation',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.greenDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    explanation,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Action ─────────────────────────────────────────
          if (!isResolved)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: hasResponded
                        ? AppColors.border
                        : AppColors.green,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor:
                      hasResponded ? AppColors.text : AppColors.green,
                ),
                icon: Icon(
                  hasResponded
                      ? Icons.edit_note_rounded
                      : Icons.rate_review_rounded,
                  size: 20,
                ),
                label: Text(
                  hasResponded
                      ? 'Modify Explanation'
                      : 'Submit Explanation',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: reportId.isEmpty
                    ? null
                    : () => _showFeedbackModal(reportId, explanation),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: AppColors.green,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This case has been resolved. No further action '
                      'is needed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontStyle: FontStyle.italic,
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

  // ============================================================
  // FEEDBACK MODAL
  // ============================================================
  void _showFeedbackModal(String reportId, String existing) {
    final controller = TextEditingController(text: existing);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              bool saving = false;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Submit Driver Explanation',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Provide your perspective or context regarding '
                    'this incident. Your response will be reviewed '
                    'by RTODA officers.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 5,
                    maxLength: 500,
                    enabled: !saving,
                    decoration: InputDecoration(
                      hintText: 'Type your statement here…',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.green,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) return;

                              setModalState(() => saving = true);
                              try {
                                await _submitFeedback(reportId, text);
                                if (!mounted) return;
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _fetchDriverReports();
                                if (!mounted) return;
                                _showSnack(
                                  'Explanation submitted successfully.',
                                );
                              } catch (e) {
                                if (!mounted) return;
                                setModalState(() => saving = false);
                                _showSnack(
                                  'Failed to submit explanation: $e',
                                  error: true,
                                );
                              }
                            },
                      child: saving
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Saving…'),
                              ],
                            )
                          : const Text(
                              'Submit Statement',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _openEvidence(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain),
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
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}