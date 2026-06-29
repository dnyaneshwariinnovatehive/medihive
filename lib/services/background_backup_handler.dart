import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'google_auth_service.dart';
import 'google_drive_sync_service.dart';
import 'daily_summary_service.dart';
import 'local_notification_service.dart';
import '../models/appointment_model.dart';

const String _dailyBackupTask = 'dailyBackup';
const String _morningSummaryTask = 'morningSummary';
const String _eveningSummaryTask = 'eveningSummary';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Background task started: $task');

    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Hive.initFlutter();

      Hive.registerAdapter(AppointmentModelAdapter());

      await Hive.openBox<AppointmentModel>('appointments');
      await Hive.openBox('drafts');
      await Hive.openBox('day_notes');

      await LocalNotificationService().init();

      switch (task) {
        case _morningSummaryTask:
          await DailySummaryService.sendMorningSummary();
          await DailySummaryService.scheduleTodayClinicalReminders();
          debugPrint('Morning summary sent');
          return true;

        case _eveningSummaryTask:
          await DailySummaryService.sendEveningSummary();
          debugPrint('Evening summary sent');
          return true;

        default:
          final googleAuth = GoogleAuthService();
          final signedIn = await googleAuth.isSignedIn();

          if (signedIn) {
            final driveService = GoogleDriveSyncService();
            await driveService.syncPendingRecords();
            debugPrint('Background backup completed successfully');
            return true;
          }

          debugPrint('Background backup skipped: Google Drive not connected');
          return false;
      }
    } catch (e) {
      debugPrint('Background task "$task" failed: $e');
      return false;
    }
  });
}

Future<void> _scheduleTask({
  required String taskName,
  required int hour,
  required int minute,
}) async {
  if (kIsWeb) return;

  final now = DateTime.now();
  var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }
  final initialDelay = scheduledDate.difference(now);

  try {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
    debugPrint('Task "$taskName" scheduled at ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
  } catch (e) {
    debugPrint('Failed to schedule task "$taskName": $e');
  }
}

Future<void> scheduleDailyBackupTask(TimeOfDay time) async {
  if (kIsWeb) return;

  final now = DateTime.now();
  var scheduledDate = DateTime(
    now.year, now.month, now.day, time.hour, time.minute,
  );
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }
  final initialDelay = scheduledDate.difference(now);

  try {
    await Workmanager().registerPeriodicTask(
      _dailyBackupTask,
      _dailyBackupTask,
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
    debugPrint('Daily backup scheduled at ${time.hour}:${time.minute}');
  } catch (e) {
    debugPrint('Failed to schedule daily backup: $e');
  }
}

Future<void> scheduleMorningSummaryTask() => _scheduleTask(
  taskName: _morningSummaryTask,
  hour: 8,
  minute: 0,
);

Future<void> scheduleEveningSummaryTask() => _scheduleTask(
  taskName: _eveningSummaryTask,
  hour: 18,
  minute: 0,
);

Future<void> cancelDailyBackupTask() async {
  if (kIsWeb) return;
  try {
    await Workmanager().cancelByUniqueName(_dailyBackupTask);
  } catch (_) {}
}

Future<void> cancelSummaryTasks() async {
  if (kIsWeb) return;
  try {
    await Workmanager().cancelByUniqueName(_morningSummaryTask);
    await Workmanager().cancelByUniqueName(_eveningSummaryTask);
  } catch (_) {}
}
