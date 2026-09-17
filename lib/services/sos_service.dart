import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class SOSService {
  static final _db = Supabase.instance.client;

  static Future<void> sendSOS({
    required String userRole,
    double? latitude,
    double? longitude,
    String? locationName,
    String? description,
  }) async {
    final user = _db.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in to send an SOS.');
    }

    // Save SOS alert
    final response = await _db
        .from('sos_alerts')
        .insert({
          'user_id': user.id,
          'user_role': userRole,
          'latitude': latitude,
          'longitude': longitude,
          'location_name': locationName,
          'description': description,
          'status': 'Pending',
        })
        .select()
        .single();

    final sosId = response['id'];

    // Notify Admin + Staff
    try {
      await NotificationService.sendPushToRole(
        role: 'admin_staff',
        title: '🚨 SOS Alert',
        message:
            '$userRole user has triggered an SOS alert.'
            '${locationName != null ? ' Location: $locationName.' : ''}',
        type: 'sos',
      );
    } catch (e) {
      debugPrint('SOS notification error: $e');
      // SOS is already saved, so don't delete it
    }

    debugPrint('SOS created: $sosId');
  }

  static Future<Map<String, dynamic>?> getActiveSOS() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;

    return await _db
        .from('sos_alerts')
        .select()
        .eq('user_id', user.id)
        .inFilter('status', ['Pending', 'Responding'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<void> cancelSOS(int sosId) async {
    await _db
        .from('sos_alerts')
        .update({'status': 'Cancelled'})
        .eq('id', sosId);
  }
}