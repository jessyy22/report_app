import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  // Singleton — ensures one subscription across the app.
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedAppSub;

  String? _listeningUserId;
  bool _messageListenersAttached = false;

  // ============================================================
  // INITIALIZE
  // ============================================================
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

      // Refresh listener — always writes to the *current* user.
      if (_listeningUserId != user.id) {
        await _tokenSubscription?.cancel();
        _listeningUserId = user.id;

        _tokenSubscription = _messaging.onTokenRefresh.listen(
          (newToken) async {
            debugPrint('FCM: Token refreshed.');

            final currentUser = _supabase.auth.currentUser;
            if (currentUser == null) {
              debugPrint('FCM: Token refreshed but no user — ignoring.');
              return;
            }

            await _saveToken(userId: currentUser.id, token: newToken);
          },
          onError: (error) {
            debugPrint('FCM refresh listener error: $error');
          },
        );
      }

      _attachMessageListeners();
    } catch (e, stackTrace) {
      debugPrint('FCM INITIALIZATION ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ============================================================
  // MESSAGE LISTENERS
  // ============================================================
  void _attachMessageListeners() {
    if (_messageListenersAttached) return;
    _messageListenersAttached = true;

    _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        'FCM: Foreground message: '
        '${message.notification?.title}',
      );

      // TODO: Show a local notification banner or in-app snackbar.
      // Requires flutter_local_notifications or an overlay.
    });

    _onOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('FCM: Notification tapped: ${message.data}');

      // TODO: Navigate to the relevant screen based on message.data.
    });

    // App launched from terminated state via notification.
    _messaging.getInitialMessage().then((message) {
      if (message == null) return;

      debugPrint('FCM: Launched from notification: ${message.data}');

      // TODO: Navigate to the relevant screen.
    });
  }

  // ============================================================
  // SAVE TOKEN
  // ============================================================
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
      final result = await _supabase.from('user_devices').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,fcm_token').select();

      if (result.isNotEmpty) {
        debugPrint('FCM: Token saved for user $userId');
      } else {
        debugPrint('FCM: Upsert returned no rows — possible RLS issue.');
      }
    } catch (e, stackTrace) {
      debugPrint('FCM SAVE ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ============================================================
  // SIGN OUT (call before auth.signOut())
  // ============================================================
  Future<void> signOut() async {
    final user = _supabase.auth.currentUser;

    if (user != null) {
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _supabase
              .from('user_devices')
              .delete()
              .eq('user_id', user.id)
              .eq('fcm_token', token);
          debugPrint('FCM: Token removed for user ${user.id}');
        }
      } catch (e) {
        debugPrint('FCM: Failed to remove token on sign-out: $e');
      }
    }

    // Also invalidate the local FCM token so the next user gets a fresh one.
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('FCM: Failed to delete local token: $e');
    }

    await dispose();
  }

  // ============================================================
  // DISPOSE
  // ============================================================
  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _onMessageSub?.cancel();
    await _onOpenedAppSub?.cancel();

    _tokenSubscription = null;
    _onMessageSub = null;
    _onOpenedAppSub = null;
    _listeningUserId = null;
    _messageListenersAttached = false;
  }
}
