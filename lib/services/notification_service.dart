import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends RTODA notifications through the Supabase Edge Function.
/// Firebase service-account credentials stay inside Supabase.
class NotificationService {
  static final SupabaseClient _db = Supabase.instance.client;

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

  static Future<void> _invoke(Map<String, dynamic> body) async {
    final response = await _db.functions.invoke(
      'rapid-handler',
      body: body,
    );

    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Notification request failed: $data');
    }

    if (data is Map && data['success'] == false) {
      throw Exception(
        data['error'] ?? data['message'] ?? 'Notification failed',
      );
    }
  }
}
