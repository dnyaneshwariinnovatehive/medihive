import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/appointment_model.dart';
import '../repositories/calendar_notes_repository.dart';
import 'local_notification_service.dart' as local_notif;
import 'shared_notification_plugin.dart';

class DailySummaryService {
  DailySummaryService._();

  static const _morningSummaryId = 9001;
  static const _eveningSummaryId = 9002;
  static const int _clinicalStartHour = 8;
  static const int _clinicalEndHour = 19;

  static int _todayFollowUpCount() {
    try {
      final box = Hive.box<AppointmentModel>('appointments');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return box.values.where((a) {
        final aptDate = DateTime(
          a.dateTime.year, a.dateTime.month, a.dateTime.day,
        );
        return a.notes == 'Follow-up' && aptDate == today;
      }).length;
    } catch (_) {
      return 0;
    }
  }

  static String _hiveKeyToSqlDate(int year, int month, int day) {
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  static Future<List<String>> _notesForDate(int year, int month, int day) async {
    try {
      final repo = CalendarNotesRepository();
      final sqlDate = _hiveKeyToSqlDate(year, month, day);
      final row = await repo.getByDate(sqlDate);
      if (row == null) return [];
      final noteText = row['note_text'] as String? ?? '';
      if (noteText.isEmpty) return [];
      final decoded = jsonDecode(noteText);
      if (decoded is List) return decoded.cast<String>();
      return [noteText];
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> _todayNotes() => _notesForDate(
    DateTime.now().year, DateTime.now().month, DateTime.now().day,
  );

  static int _clinicalReminderId(int year, int month, int day, int hour) =>
      'clinical_${year}_${month}_${day}_$hour'.hashCode & 0x7FFFFFFF;

  static Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'clinical_reminders',
      'Clinical Reminders',
      channelDescription: 'Reminders for your clinical notes',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await sharedNotificationPlugin.show(id, title, body, details);
  }

  static Future<void> sendMorningSummary() async {
    if (kIsWeb) return;

    final followUpCount = _todayFollowUpCount();
    final notes = await _todayNotes();

    final buffer = StringBuffer();
    if (followUpCount > 0) {
      buffer.write('$followUpCount follow-up${followUpCount == 1 ? '' : 's'} due today');
    }
    if (notes.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' • ');
      buffer.write('${notes.length} clinical note${notes.length == 1 ? '' : 's'}');
    }

    final body = buffer.isNotEmpty
        ? 'You have $buffer'
        : 'No follow-ups or notes scheduled for today';

    await local_notif.LocalNotificationService().showNotification(
      id: _morningSummaryId,
      title: 'Good Morning, Doctor',
      body: body,
    );
  }

  static Future<void> sendEveningSummary() async {
    if (kIsWeb) return;

    final followUpCount = _todayFollowUpCount();
    final notes = await _todayNotes();

    final buffer = StringBuffer();
    if (followUpCount > 0) {
      buffer.write('$followUpCount follow-up${followUpCount == 1 ? '' : 's'}');
    }
    if (notes.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' • ');
      buffer.write('${notes.length} clinical note${notes.length == 1 ? '' : 's'}');
    }

    final body = buffer.isNotEmpty
        ? 'Today you had $buffer'
        : 'No follow-ups or clinical notes recorded today';

    await local_notif.LocalNotificationService().showNotification(
      id: _eveningSummaryId,
      title: 'End of Day Summary',
      body: body,
    );
  }

  /// Schedules hourly clinical note reminders from 8:00 AM to 7:00 PM
  /// for the given date. Skips hours that have already passed.
  /// Shows an immediate notification if called during the current hour window.
  static Future<void> scheduleNoteReminder({
    required int year,
    required int month,
    required int day,
    required String noteText,
  }) async {
    if (kIsWeb) return;

    final targetDate = DateTime(year, month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Only schedule for today's date
    if (targetDate != today) return;

    // Collect all notes for today
    final allNotes = await _notesForDate(year, month, day);

    // Cancel existing reminders for today to avoid duplicates
    await cancelNoteReminder(year, month, day);

    tz_data.initializeTimeZones();

    for (int hour = _clinicalStartHour; hour <= _clinicalEndHour; hour++) {
      final scheduleTime = DateTime(year, month, day, hour, 0);
      final notifId = _clinicalReminderId(year, month, day, hour);

      final body = allNotes.isNotEmpty
          ? allNotes.join('\n')
          : noteText;

      if (hour == now.hour) {
        await _showNotification(
          id: notifId,
          title: 'Clinical Reminder ($hour:00)',
          body: body,
        );
      } else if (scheduleTime.isBefore(now)) {
        continue;
      } else {
        final tzTarget = tz.TZDateTime.from(scheduleTime, tz.local);
        try {
          await sharedNotificationPlugin.zonedSchedule(
            notifId,
            'Clinical Reminder ($hour:00)',
            body,
            tzTarget,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'clinical_reminders',
                'Clinical Reminders',
                channelDescription: 'Reminders for your clinical notes',
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          debugPrint('Clinical reminder scheduled for $year-$month-$day at $hour:00');
        } catch (e) {
          debugPrint('Failed to schedule clinical reminder at $hour:00: $e');
        }
      }
    }
  }

  /// Cancels all hourly clinical reminders for the given date.
  static Future<void> cancelNoteReminder(int year, int month, int day) async {
    for (int hour = _clinicalStartHour; hour <= _clinicalEndHour; hour++) {
      await sharedNotificationPlugin.cancel(
        _clinicalReminderId(year, month, day, hour),
      );
    }
  }

  /// Called from morning summary task to schedule hourly reminders
  /// if clinical notes exist for today.
  static Future<void> scheduleTodayClinicalReminders() async {
    if (kIsWeb) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notes = await _todayNotes();

    if (notes.isEmpty) return;

    await cancelNoteReminder(
      today.year, today.month, today.day,
    );

    tz_data.initializeTimeZones();

    for (int hour = _clinicalStartHour; hour <= _clinicalEndHour; hour++) {
      final scheduleTime = DateTime(
        today.year, today.month, today.day, hour, 0,
      );
      final notifId = _clinicalReminderId(
        today.year, today.month, today.day, hour,
      );

      if (scheduleTime.isBefore(now)) continue;

      final body = notes.join('\n');
      final tzTarget = tz.TZDateTime.from(scheduleTime, tz.local);

      try {
        await sharedNotificationPlugin.zonedSchedule(
          notifId,
          'Clinical Reminder ($hour:00)',
          body,
          tzTarget,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'clinical_reminders',
              'Clinical Reminders',
              channelDescription: 'Reminders for your clinical notes',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint('Clinical reminder scheduled for today at $hour:00');
      } catch (e) {
        debugPrint('Failed to schedule clinical reminder at $hour:00: $e');
      }
    }
  }
}
