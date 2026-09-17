import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final db = Supabase.instance.client;
  Stream<List<Map<String, dynamic>>>? stream;
  bool markingAll = false;

  @override
  void initState() {
    super.initState();
    final user = db.auth.currentUser;
    if (user != null) {
      stream = db
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (stream != null)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (_, s) {
                final list = s.data ?? [];
                final unread = list.where((n) => n['is_read'] != true).length;
                if (unread == 0) return const SizedBox();
                return TextButton(
                  onPressed: markingAll ? null : () => _markAll(list),
                  child: markingAll
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Mark all read',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                );
              },
            ),
        ],
      ),
      body: stream == null
          ? _empty(
              Icons.lock_outline,
              'Please log in',
              'Log in to view your RTODA notifications.',
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (_, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (s.hasError) {
                  return _empty(
                    Icons.cloud_off_rounded,
                    'Notifications unavailable',
                    'Please check your connection and try again.',
                  );
                }

                final list = s.data ?? [];

                if (list.isEmpty) {
                  return _empty(
                    Icons.notifications_none_rounded,
                    'You’re all caught up',
                    'Your RTODA updates will appear here.',
                  );
                }

                final unread = list.where((n) => n['is_read'] != true).length;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _summary(unread, list.length),
                    const SizedBox(height: 20),
                    const RTODASectionTitle(
                      title: 'Recent updates',
                      subtitle: 'Your latest RTODA notifications.',
                    ),
                    const SizedBox(height: 12),
                    ...list.map(_card),
                  ],
                );
              },
            ),
    );
  }

  Widget _summary(int unread, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_rounded,
            color: AppColors.green,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            unread == 0
                ? 'All caught up'
                : '$unread unread notification${unread == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> n) {
    final title = '${n['title'] ?? 'RTODA Update'}';
    final message = '${n['message'] ?? ''}';
    final type = '${n['type'] ?? 'general'}'.toLowerCase();
    final read = n['is_read'] == true;
    final time = _time(n['created_at']?.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: read ? 0 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: read ? Colors.black12 : AppColors.green.withOpacity(.18),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _markRead(n),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: read ? Colors.grey.shade100 : AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _icon(type),
                  color: read ? Colors.grey : AppColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (!read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(String type) {
    switch (type) {
      case 'sos':
        return Icons.warning_rounded;
      case 'report':
        return Icons.receipt_long_rounded;
      case 'report_resolved':
        return Icons.check_circle_rounded;
      case 'report_dismissed':
        return Icons.info_rounded;
      case 'account_approved':
        return Icons.verified_rounded;
      case 'account_rejected':
        return Icons.cancel_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      case 'account':
        return Icons.person_rounded;
      case 'system':
        return Icons.settings_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['id'] == null || n['is_read'] == true) return;

    try {
      await db
          .from('notifications')
          .update({'is_read': true})
          .eq('id', n['id']);
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }

  Future<void> _markAll(List<Map<String, dynamic>> list) async {
    final user = db.auth.currentUser;
    if (user == null) return;

    setState(() => markingAll = true);

    try {
      await db
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Mark all error: $e');
    }

    if (mounted) setState(() => markingAll = false);
  }

  String _time(String? value) {
    if (value == null || value.isEmpty) return 'Just now';

    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;

    final diff = DateTime.now().difference(date);

    if (diff.inSeconds < 30) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Widget _empty(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              child: Icon(icon, color: AppColors.green, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
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
