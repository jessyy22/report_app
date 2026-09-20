import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<String>? _tokenSubscription;
  String? _listeningUserId;

  Future<void> initialize() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      debugPrint('FCM: No logged-in user.');
      return;
    }

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('FCM permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM: Permission denied.');
        return;
      }

      final token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        debugPrint('FCM: Token is null or empty.');
        return;
      }

      debugPrint('FCM: Token obtained.');
      await _saveToken(userId: user.id, token: token);

      if (_listeningUserId != user.id) {
        await _tokenSubscription?.cancel();
        _listeningUserId = user.id;

        _tokenSubscription = _messaging.onTokenRefresh.listen(
          (newToken) {
            debugPrint('FCM: Token refreshed.');
            _saveToken(userId: user.id, token: newToken);
          },
          onError: (error) {
            debugPrint('FCM refresh listener error: $error');
          },
        );
      }
    } catch (e, stackTrace) {
      debugPrint('FCM INITIALIZATION ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _saveToken({
    required String userId,
    required String token,
  }) async {
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.android
        ? 'android'
        : defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'unknown';

    try {
      await _supabase.from('user_devices').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': platform,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');

      final saved = await _supabase
          .from('user_devices')
          .select('user_id')
          .eq('user_id', userId)
          .eq('fcm_token', token)
          .maybeSingle();

      if (saved == null) {
        debugPrint(
          'FCM: Upsert completed, but token was not found on verification.',
        );
      } else {
        debugPrint('FCM: Token saved and verified for user $userId.');
      }
    } catch (e, stackTrace) {
      debugPrint('FCM SAVE ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _listeningUserId = null;
  }
}
