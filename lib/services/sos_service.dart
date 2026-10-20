import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class SOSService {
  static final _db = Supabase.instance.client;

  /// Sends an SOS alert.
  ///
  /// [latitude] / [longitude] are nullable — if GPS fails, the alert is
  /// still saved and dispatched with location unknown.
  static Future<void> sendSOS({
    required String userRole,
    double? latitude,
    double? longitude,
    String? locationName,
    String? description,
    String? driverBodyNumber,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in to send an SOS.');
    }

    // Truncate very long addresses so the push payload stays under limits.
    final safeLocation = locationName != null && locationName.trim().isNotEmpty
        ? (locationName.length > 120
              ? '${locationName.substring(0, 120)}…'
              : locationName.trim())
        : null;

    final safeDescription = description != null && description.trim().isNotEmpty
        ? (description.length > 500
              ? '${description.substring(0, 500)}…'
              : description.trim())
        : null;

    late final Map<String, dynamic> response;

    try {
      response = await _db
          .from('sos_alerts')
          .insert({
            'user_id': user.id,
            'user_role': userRole,
            'body_number': driverBodyNumber,
            'latitude': latitude,
            'longitude': longitude,
            'location_name': safeLocation,
            'description': safeDescription,
            'status': 'Pending',
          })
          .select()
          .single()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception(
              'Server did not respond. Check your connection and try again.',
            ),
          );
    } catch (e) {
      debugPrint('SOS insert failed: $e');
      rethrow;
    }

    final sosId = response['id'];

    // Build a role-aware message
    final String message;
    if (userRole == 'driver' && driverBodyNumber != null) {
      message =
          'Driver $driverBodyNumber has triggered an SOS alert.'
          '${safeLocation != null ? ' Location: $safeLocation.' : ''}';
    } else {
      message =
          '$userRole user has triggered an SOS alert.'
          '${safeLocation != null ? ' Location: $safeLocation.' : ''}';
    }

    try {
      await NotificationService.sendPushToRole(
        role: 'admin_staff',
        title: '🚨 SOS Alert',
        message: message,
        type: 'sos',
      );
    } catch (e) {
      debugPrint('SOS notification error (admin_staff): $e');

      try {
        await NotificationService.sendPushToRole(
          role: 'admin',
          title: '🚨 SOS Alert (fallback)',
          message: message,
          type: 'sos',
        );
      } catch (e2) {
        debugPrint('SOS notification error (admin fallback): $e2');
      }
    }

    debugPrint('SOS created: $sosId');
  }

  /// Returns the most recent active SOS alert for the current user.
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

  /// Cancels an SOS alert.
  static Future<void> cancelSOS(dynamic sosId) async {
    await _db
        .from('sos_alerts')
        .update({'status': 'Cancelled'})
        .eq('id', sosId);
  }
}
