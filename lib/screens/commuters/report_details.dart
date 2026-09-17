import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';

class ReportDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> report;
  const ReportDetailsScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final status = (report['status'] ?? 'Pending').toString();
    final id = report['report_id']?.toString() ?? 'N/A';
    final feedback = (report['driver_feedback'] ?? '').toString();
    final evidence = (report['evidence_url'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Report Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text('#$id', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), RTODAStatusBadge(status: status)]),
                const SizedBox(height: 8),
                Text((report['violation'] ?? 'Unspecified violation').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Report progress', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: _timeline(status))),
          const SizedBox(height: 14),
          const Text('Incident information', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            _row('Body number', report['body_number']),
            _row('Violation', report['violation']),
            _row('Incident date', report['incidentdate']),
            _row('Incident time', report['incidenttime']),
            _row('Location', report['location']),
            _row('Description', report['description']),
          ]))),
          if (feedback.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Driver response', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(feedback, style: const TextStyle(height: 1.45, color: AppColors.text)))),
          ],
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Evidence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(evidence, height: 220, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 180, color: AppColors.background, alignment: Alignment.center, child: const Text('Evidence could not be loaded.')))),
          ],
        ],
      ),
    );
  }

  Widget _timeline(String status) {
    final stages = ['Pending', 'Under Review', 'Under Investigation', 'Resolved'];
    final normalized = status.toLowerCase();
    int current = normalized == 'dismissed' ? 3 : stages.indexWhere((s) => s.toLowerCase() == normalized);
    if (current < 0) current = normalized.contains('investigation') ? 2 : normalized.contains('review') ? 1 : normalized == 'resolved' ? 3 : 0;
    return Column(children: [
      for (int i = 0; i < stages.length; i++) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: i <= current ? AppColors.green : Colors.grey.shade200), child: Icon(i <= current ? Icons.check_rounded : Icons.circle, size: i <= current ? 17 : 8, color: i <= current ? Colors.white : Colors.grey.shade500)),
            if (i < stages.length - 1) Container(width: 2, height: 30, color: i < current ? AppColors.green : Colors.grey.shade200),
          ]),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(top: 3), child: Text(stages[i], style: TextStyle(fontWeight: i <= current ? FontWeight.w700 : FontWeight.w500, color: i <= current ? AppColors.text : AppColors.muted))),
        ]),
      ],
      if (status.toLowerCase() == 'dismissed') Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [const SizedBox(width: 38), Text('This report was dismissed.', style: TextStyle(color: AppColors.muted, fontSize: 12))])),
    ]);
  }

  Widget _row(String label, dynamic value) {
    final text = value == null || value.toString().trim().isEmpty ? 'Not provided' : value.toString();
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 105, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600))), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))]));
  }
}
