import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/common/notifications_screen.dart';
import '../theme/app_theme.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _db = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>>? _stream;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _attachStream();

    // React to sign-in / sign-out / user switch.
    _authSub = _db.auth.onAuthStateChange.listen((_) {
      _attachStream();
    });
  }

  void _attachStream() {
    final user = _db.auth.currentUser;

    if (!mounted) return;

    if (user == null) {
      setState(() => _stream = null);
      return;
    }

    // Explicitly typed so Dart can infer the correct Stream type.
    final Stream<List<Map<String, dynamic>>> stream = _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    setState(() {
      _stream = stream;
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) {
      return IconButton(
        tooltip: 'Notifications',
        icon: const Icon(Icons.notifications_none_rounded),
        onPressed: _openNotifications,
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        // Handle stream errors gracefully.
        if (snapshot.hasError) {
          debugPrint('Notifications stream error: ${snapshot.error}');
          return IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: _openNotifications,
          );
        }

        // Client-side filter — the stream loads all, we count the unread.
        final notifications = snapshot.data ?? [];
        final recent = notifications.take(100).toList();
        final unread = recent.where((n) => n['is_read'] != true).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: unread > 0
                  ? '$unread unread notifications'
                  : 'Notifications',
              icon: Icon(
                unread > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
              ),
              onPressed: _openNotifications,
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Container(
                    key: ValueKey(unread),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            Theme.of(context).appBarTheme.backgroundColor ??
                            Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }
}
