import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverReportsPage extends StatefulWidget {
  final String bodyNumber;

  const DriverReportsPage({super.key, required this.bodyNumber});

  @override
  State<DriverReportsPage> createState() => _DriverReportsPageState();
}

class _DriverReportsPageState extends State<DriverReportsPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<dynamic> _reports = [];

  @override
  void initState() {
    super.initState();
    _fetchDriverReports();
  }

  Future<void> _fetchDriverReports() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('reports')
          .select(
            'report_id, violation, location, status, incidentdate, incidenttime, evidence_url, driver_feedback',
          )
          .eq('body_number', widget.bodyNumber)
          .order('incidentdate', ascending: false);

      setState(() {
        _reports = data ?? [];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading reports: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitFeedback(String reportId, String feedbackText) async {
    try {
      await supabase
          .from('reports')
          .update({'driver_feedback': feedbackText})
          .eq('report_id', reportId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Explanation submitted successfully.'),
          backgroundColor: Colors.green,
        ),
      );

      _fetchDriverReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit explanation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showFeedbackModal(
    BuildContext context,
    String reportId,
    String existingFeedback,
  ) {
    final TextEditingController feedbackController = TextEditingController(
      text: existingFeedback,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Submit Driver Explanation",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Provide your perspective or context regarding this incident. Your response will be reviewed by RTODA officers.",
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: feedbackController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: "Type your statement here...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.green.shade700,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (feedbackController.text.trim().isNotEmpty) {
                      _submitFeedback(reportId, feedbackController.text.trim());
                      Navigator.pop(context);
                    }
                  },
                  child: const Text(
                    "Submit Statement",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text(
          "My Report History",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _reports.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reports.length,
              itemBuilder: (context, index) {
                final report = _reports[index];
                return _buildReportCard(report);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_turned_in_rounded,
            size: 72,
            color: Colors.green.shade200,
          ),
          const SizedBox(height: 16),
          const Text(
            "All Clear!",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "No commuter complaints have been filed against your body number.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(dynamic report) {
    final String status = report['status'] ?? 'Pending';
    final String explanation = report['driver_feedback'] ?? '';
    final bool hasResponded = explanation.isNotEmpty;

    final String incidentDate = report['incidentdate'] ?? 'Unknown Date';
    final String incidentTime = report['incidenttime'] ?? '';
    final String? evidenceUrl = report['evidence_url'];

    Color statusColor = Colors.orange;
    if (status == 'Resolved') statusColor = Colors.green;
    if (status == 'Under Review' || status == 'Summoned')
      statusColor = Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  report['violation'] ?? 'Unspecified Incident',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Location row
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 14,
                color: Colors.black38,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  report['location'] ?? 'Unknown Location',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Date and Time row
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: Colors.black38,
              ),
              const SizedBox(width: 4),
              Text(
                "$incidentDate ${incidentTime.isNotEmpty ? '• $incidentTime' : ''}",
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),

          // Evidence Image Thumbnail if available
          if (evidenceUrl != null && evidenceUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                evidenceUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ],

          const Divider(height: 24),

          if (hasResponded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade100, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Your Explanation Statement:",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    explanation,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: hasResponded
                      ? Colors.grey.shade400
                      : Colors.green.shade600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(
                hasResponded
                    ? Icons.edit_note_rounded
                    : Icons.rate_review_rounded,
                color: hasResponded ? Colors.black87 : Colors.green.shade700,
                size: 20,
              ),
              label: Text(
                hasResponded ? "Modify Explanation" : "Submit Explanation",
                style: TextStyle(
                  color: hasResponded ? Colors.black87 : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () => _showFeedbackModal(
                context,
                report['report_id'].toString(),
                explanation,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
