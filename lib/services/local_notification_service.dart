import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'shared_notification_plugin.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await initializePluginOnce(initSettings);
    await _requestPermissions();
    _initialized = true;
  }

  Future<bool> _requestPermissions() async {
    final android = sharedNotificationPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
    }
    final ios = sharedNotificationPlugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      await ios.requestPermissions(alert: true, badge: true, sound: true);
    }
    return true;
  }

  Future<void> scheduleAppointmentReminder({
    required String id,
    required String patientName,
    required DateTime appointmentTime,
  }) async {
    if (!_initialized) await init();

    final remindAt = appointmentTime.subtract(const Duration(minutes: 10));
    final now = DateTime.now();
    if (remindAt.isBefore(now)) return;

    await _requestPermissions();

    final diff = remindAt.difference(now);
    final tzNow = tz.TZDateTime.now(tz.UTC);
    final tzRemindAt = tzNow.add(diff);

    const androidDetails = AndroidNotificationDetails(
      'appointment_reminder',
      'Appointment Reminders',
      channelDescription: 'Reminders for upcoming appointments',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await sharedNotificationPlugin.zonedSchedule(
        id.hashCode,
        'Appointment Reminder',
        'You have an appointment with $patientName in 10 minutes',
        tzRemindAt,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('LocalNotificationService: exact schedule failed, fallback: $e');
      await sharedNotificationPlugin.zonedSchedule(
        id.hashCode,
        'Appointment Reminder',
        'You have an appointment with $patientName in 10 minutes',
        tzRemindAt,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelAppointmentReminder(String id) async {
    await sharedNotificationPlugin.cancel(id.hashCode);
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();
    await _requestPermissions();

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

    await sharedNotificationPlugin.show(id, title, body, details,
        payload: payload);
  }

  Future<void> cancelAll() async {
    await sharedNotificationPlugin.cancelAll();
  }
}
