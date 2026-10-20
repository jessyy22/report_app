import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends RTODA notifications through the Supabase Edge Function.
/// Firebase service-account credentials stay inside Supabase.
class NotificationService {
  static final SupabaseClient _db = Supabase.instance.client;

  // ============================================================
  // PUBLIC API
  // ============================================================

  static Future<void> sendPush({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
  }) async {
    await _invoke({
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type,
    });
  }

  static Future<void> sendPushToRole({
    required String role,
    required String title,
    required String message,
    String type = 'general',
  }) async {
    await _invoke({
      'role': role,
      'title': title,
      'message': message,
      'type': type,
    });
  }

  // ============================================================
  // INTERNAL
  // ============================================================

  static Future<void> _invoke(Map<String, dynamic> body) async {
    // Skip silently if not authenticated — notifications are
    // best-effort and shouldn't fail the calling operation.
    final session = _db.auth.currentSession;
    if (session == null) {
      debugPrint('Notification skipped: no session');
      return;
    }

    final recipient = body['user_id'] ?? body['role'] ?? 'unknown';
    final type = body['type'] ?? 'general';
    final title = body['title'] ?? '(no title)';

    debugPrint('Notification → $recipient ($type): $title');

    try {
      final response = await _db.functions
          .invoke('rapid-handler', body: body)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Notification timed out after 10s'),
          );

      final data = response.data;

      if (response.status < 200 || response.status >= 300) {
        debugPrint(
          'Notification FAILED ($recipient): '
          'status=${response.status} data=$data',
        );
        throw NotificationException(
          'Notification request failed',
          cause: data,
          statusCode: response.status,
        );
      }

      if (data is Map) {
        final success = data['success'];
        // Only treat as failure if success == false (explicitly)
        // or if success is missing but an error key exists.
        if (success == false || (success == null && data['error'] != null)) {
          final msg =
              data['error']?.toString() ??
              data['message']?.toString() ??
              'Notification failed';
          debugPrint('Notification FAILED ($recipient): $msg');
          throw NotificationException(msg, cause: data);
        }
      }

      debugPrint('Notification OK ($recipient)');
    } on TimeoutException {
      debugPrint('Notification TIMEOUT ($recipient)');
      rethrow;
    } on NotificationException {
      rethrow;
    } catch (e) {
      debugPrint('Notification ERROR ($recipient): $e');
      throw NotificationException('Notification service error', cause: e);
    }
  }
}

// ============================================================
// Typed exception
// ============================================================
class NotificationException implements Exception {
  final String message;
  final Object? cause;
  final int? statusCode;

  NotificationException(this.message, {this.cause, this.statusCode});

  @override
  String toString() =>
      'NotificationException: $message'
      '${statusCode != null ? ' (status: $statusCode)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}
