import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'supabase_service.dart';

/// Firebase Cloud Messaging service
class FcmService {
  final SupabaseService _supabaseService;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  String? _fcmToken;

  FcmService(this._supabaseService)
    : _messaging = FirebaseMessaging.instance,
      _localNotifications = FlutterLocalNotificationsPlugin();

  String? get fcmToken => _fcmToken;

  /// Initialize FCM
  Future<void> initialize() async {
    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('FCM: User declined permission');
      return;
    }

    // Initialize local notifications
    await _initLocalNotifications();

    // Get FCM token
    _fcmToken = await _messaging.getToken();
    debugPrint('FCM Token: $_fcmToken');

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background message tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check for initial message (app opened from terminated state)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels for Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    // Main channel
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'hatid_sundo_channel',
        'Hatid Sundo',
        description: 'Ride notifications',
        importance: Importance.high,
      ),
    );

    // Chat channel
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'hatid_sundo_chat',
        'Chat Messages',
        description: 'New message notifications',
        importance: Importance.high,
      ),
    );

    // Ride request channel
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'hatid_sundo_rides',
        'Ride Requests',
        description: 'New ride request notifications',
        importance: Importance.max,
      ),
    );
  }

  /// Handle FCM token refresh
  Future<void> _onTokenRefresh(String token) async {
    _fcmToken = token;
    await _saveTokenToDatabase();
  }

  /// Save FCM token to database
  Future<void> _saveTokenToDatabase() async {
    final userId = _supabaseService.currentUserId;
    if (userId == null || _fcmToken == null) return;

    await _supabaseService.from('user_fcm_tokens').upsert(
      {
        'user_id': userId,
        'token': _fcmToken,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id, token',
    );
  }

  /// Handle foreground message with type-specific behavior
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM Foreground: ${message.notification?.title}');
    final type = message.data['type'] ?? 'general';

    // Determine notification channel and behavior based on type
    String channelId = 'hatid_sundo_channel';
    Importance importance = Importance.high;

    switch (type) {
      case 'chat_message':
        channelId = 'hatid_sundo_chat';
        break;
      case 'new_ride_request':
      case 'ride_request':
        channelId = 'hatid_sundo_rides';
        importance = Importance.max;
        break;
      case 'trip_cancelled':
        importance = Importance.max;
        break;
      case 'rider_status':
      case 'driver_assigned':
      case 'driver_arriving':
      case 'trip_started':
      case 'trip_completed':
        break;
    }

    // Show local notification
    _showLocalNotification(
      title: message.notification?.title ?? 'Hatid Sundo',
      body: message.notification?.body ?? '',
      payload: jsonEncode(message.data),
      channelId: channelId,
      importance: importance,
    );

    // Store notification in database
    _storeNotification(message);
  }

  /// Handle message opened app — navigate to relevant screen
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('FCM Opened: ${message.data}');
    // Navigation is handled by the GoRouter redirect logic
    // which checks for active trips. The notification payload
    // contains trip_id which can be used for deep linking.
    // For now, the app will naturally redirect to the active trip
    // screen when it detects an active trip on startup.
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      debugPrint('Notification tapped: $data');
      // The app's router redirect will handle navigation
      // to the correct screen based on active trip state
    }
  }

  /// Show local notification with configurable channel
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = 'hatid_sundo_channel',
    Importance importance = Importance.high,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'hatid_sundo_chat'
          ? 'Chat Messages'
          : channelId == 'hatid_sundo_rides'
          ? 'Ride Requests'
          : 'Hatid Sundo',
      channelDescription: 'Ride notifications',
      importance: importance,
      priority: importance == Importance.max ? Priority.max : Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Store notification in database
  Future<void> _storeNotification(RemoteMessage message) async {
    final userId = _supabaseService.currentUserId;
    if (userId == null) return;

    await _supabaseService.from(AppConstants.notificationsTable).insert({
      'user_id': userId,
      'type': message.data['type'] ?? 'general',
      'title': message.notification?.title ?? '',
      'body': message.notification?.body ?? '',
      'payload': message.data,
      'read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }

  /// Update token on login
  Future<void> onUserLogin() async {
    await _saveTokenToDatabase();
  }

  /// Clear token on logout
  Future<void> onUserLogout() async {
    final userId = _supabaseService.currentUserId;
    if (userId != null && _fcmToken != null) {
      await _supabaseService
          .from('user_fcm_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', _fcmToken!);
    }
  }
}

/// FCM service provider
final fcmServiceProvider = Provider<FcmService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return FcmService(supabaseService);
});

/// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM Background: ${message.notification?.title}');
}
