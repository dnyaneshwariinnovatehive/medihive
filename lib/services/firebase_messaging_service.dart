import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'local_notification_service.dart';
import 'api_service.dart';
import 'sync_manager.dart';

class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  FirebaseMessaging? _messaging;
  String? _fcmToken;
  bool _initialized = false;

  String? get fcmToken => _fcmToken;

  Future<void> init() async {
    if (_initialized) return;

    await Firebase.initializeApp();
    _messaging = FirebaseMessaging.instance;

    await _requestPermission();
    await _getToken();
    _listenToTokenRefresh();
    _setupForegroundHandler();
    _setupBackgroundHandler();
    _setupTerminatedHandler();

    _initialized = true;
  }

  Future<void> refreshToken() async {
    _fcmToken = await _messaging?.getToken();
    if (_fcmToken != null) {
      await ApiService.updateFcmToken(_fcmToken!);
    }
  }

  Future<void> subscribeToUserTopic(String userId) async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final topic = 'sync_user_$userId';
      await messaging.subscribeToTopic(topic);
      debugPrint('FCM: Subscribed to topic $topic');
    } catch (e) {
      debugPrint('FCM: subscribeToTopic error: $e');
    }
  }

  Future<void> unsubscribeFromUserTopic(String userId) async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final topic = 'sync_user_$userId';
      await messaging.unsubscribeFromTopic(topic);
      debugPrint('FCM: Unsubscribed from topic $topic');
    } catch (e) {
      debugPrint('FCM: unsubscribeFromTopic error: $e');
    }
  }

  Future<void> _requestPermission() async {
    final messaging = _messaging;
    if (messaging == null) return;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');
  }

  Future<void> _getToken() async {
    final messaging = _messaging;
    if (messaging == null) return;

    try {
      _fcmToken = await messaging.getToken();
      if (_fcmToken != null) {
        debugPrint('FCM token obtained: ${_fcmToken!.substring(0, 20)}...');
        await ApiService.updateFcmToken(_fcmToken!);
      }
    } catch (e) {
      debugPrint('FCM getToken error: $e');
    }
  }

  void _listenToTokenRefresh() {
    _messaging?.onTokenRefresh.listen((token) {
      _fcmToken = token;
      debugPrint('FCM token refreshed');
      ApiService.updateFcmToken(token);
    });
  }

  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen(_handleMessage);
  }

  void _setupBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
  }

  void _setupTerminatedHandler() {
    FirebaseMessaging.instance.getInitialMessage().then(_handleTerminatedMessage);
  }

  Future<void> _handleMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    if (data['action'] == 'sync_now' || data['sync'] == 'true') {
      debugPrint('FCM message: triggering immediate sync');
      SyncManager().forceSyncNow();
    }

    if (notification != null) {
      await LocalNotificationService().showNotification(
        id: message.hashCode,
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: data['route'],
      );
    } else if (data.containsKey('title') && data.containsKey('body')) {
      await LocalNotificationService().showNotification(
        id: message.hashCode,
        title: data['title'] ?? '',
        body: data['body'] ?? '',
        payload: data['route'],
      );
    }

    debugPrint('FCM message received: ${notification?.title ?? data['title']}');
  }

  Future<void> _handleTerminatedMessage(RemoteMessage? message) async {
    if (message == null) return;
    await _handleMessage(message);
  }
}

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final notification = message.notification;
  final data = message.data;

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final title = notification?.title ?? data['title'] ?? 'MediHive';
  final body = notification?.body ?? data['body'] ?? '';

  const androidDetails = AndroidNotificationDetails(
    'push_notifications',
    'Push Notifications',
    channelDescription: 'Push notifications from server',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  const iosDetails = DarwinNotificationDetails();
  const details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    title,
    body,
    details,
    payload: data['route'],
  );
}
