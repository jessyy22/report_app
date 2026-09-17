import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> initialize() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      debugPrint('FCM: No logged-in user.');
      return;
    }

    // Request notification permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('FCM permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied.');
      return;
    }

    // Get FCM token
    final token = await _messaging.getToken();

    if (token == null) {
      debugPrint('FCM token is null.');
      return;
    }

    debugPrint('FCM TOKEN: $token');

    // Save token to Supabase
    await _saveToken(userId: user.id, token: token);

    // Listen for token changes
    _messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM TOKEN REFRESHED: $newToken');

      await _saveToken(userId: user.id, token: newToken);
    });
  }

  Future<void> _saveToken({
    required String userId,
    required String token,
  }) async {
    String platform;

    if (kIsWeb) {
      platform = 'web';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      platform = 'android';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platform = 'ios';
    } else {
      platform = 'unknown';
    }

    try {
      await _supabase.from('user_devices').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': platform,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');

      debugPrint('FCM token saved successfully.');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }
}
