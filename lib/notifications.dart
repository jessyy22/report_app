import 'package:flutter/material.dart';
import 'screens/common/notifications_screen.dart';

/// Backward-compatible entry point for the RTODA notification center.
class Notifications extends StatelessWidget {
  const Notifications({super.key});

  @override
  Widget build(BuildContext context) => const NotificationsScreen();
}
