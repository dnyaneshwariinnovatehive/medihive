import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'connectivity_service.dart';
import 'google_auth_service.dart';
import 'google_drive_sync_service.dart';
import '../models/appointment_model.dart';
import 'event_notification_service.dart';
import 'background_backup_handler.dart';
import '../theme/app_theme.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../repositories/patient_images_repository.dart';

enum SyncState {
  offline,
  syncing,
  synced,
  error,
}

class SyncManager extends ChangeNotifier {
  static T _tryInit<T>(String name, T Function() fn) {
    print('INIT $name START');
    try {
      final v = fn();
      print('INIT $name SUCCESS');
      return v;
    } catch (e, st) {
      print('INIT $name FAILED: $e');
      print(st);
      rethrow;
    }
  }

  final ConnectivityService _connectivityService = _tryInit('ConnectivityService', () => ConnectivityService());

  GoogleAuthService? _googleAuthService;
  GoogleAuthService get _authService {
    _googleAuthService ??= _tryInit('GoogleAuthService', () => GoogleAuthService());
    return _googleAuthService!;
  }

  GoogleDriveSyncService? _driveSyncService;
  GoogleDriveSyncService get _driveService {
    _driveSyncService ??= _tryInit('GoogleDriveSyncService', () => GoogleDriveSyncService());
    return _driveSyncService!;
  }

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  SyncState _syncState = SyncState.synced;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  StreamSubscription<bool>? _connectivitySubscription;

  final Map<String, int> _imageUploadRetries = {};

  bool _isSignedIn = false;
  StreamSubscription? _googleAuthSub;

  SyncState get syncState => _syncState;
  bool get isSyncing => _syncState == SyncState.syncing;

  final PatientRepository _patientRepo = _tryInit('PatientRepository', () => PatientRepository());
  final OpdRecordRepository _opdRepo = _tryInit('OpdRecordRepository', () => OpdRecordRepository());
  final SyncQueueRepository _syncQueueRepo = _tryInit('SyncQueueRepository', () => SyncQueueRepository());
  final PatientImagesRepository _patientImagesRepo = _tryInit('PatientImagesRepository', () => PatientImagesRepository());
  int _cachedUnsyncedCount = 0;

  static final SyncManager _instance = _tryInit('SyncManager._instance', () => SyncManager._internal());
  factory SyncManager() {
    print('FACTORY SyncManager() CALLED');
    return _instance;
  }

  SyncManager._internal() {
    print('SYNC CONSTRUCTOR ENTER');
    if (kIsWeb) {
      debugPrint('SYNC CONSTRUCTOR EXIT: kIsWeb');
      return;
    }

    _initializeState();
    _refreshUnsyncedCount();
    _initPolling();

    print('SYNC scheduling initial timer');
    Timer(const Duration(seconds: 5), () {
      print('SYNC INITIAL TIMER FIRED');
      _trySync();
    });

    _connectivitySubscription = _connectivityService.isConnected.listen((connected) {
      print('SYNC CONNECTIVITY CHANGED: $connected');
      if (!connected) {
        _syncState = SyncState.offline;
        notifyListeners();
      } else {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 3), () {
          debugPrint('SYNC CONNECTIVITY DEBOUNCE TIMER FIRED');
          _trySync();
        });
      }
    });

    _googleAuthSub = _authService.onAuthStateChanged.listen((account) {
      _isSignedIn = account != null;
      debugPrint('SYNC AUTH CHANGED: signedIn=$_isSignedIn');
      if (_isSignedIn && _connectivityService.currentStatus) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 3), () {
          debugPrint('SYNC AUTH DEBOUNCE TIMER FIRED');
          _trySync();
        });
      }
    });
    print('SYNC CONSTRUCTOR EXIT');
  }

  void _initializeState() {
    final connected = _connectivityService.currentStatus;
    _syncState = connected ? SyncState.synced : SyncState.offline;
    notifyListeners();
  }

  Future<void> _refreshUnsyncedCount() async {
    try {
      int count = await _syncQueueRepo.countPending();
      try {
        final apptBox = Hive.box<AppointmentModel>('appointments');
        count += apptBox.values.where((a) => !a.isSynced).length;
      } catch (_) {}
      _cachedUnsyncedCount = count;
      notifyListeners();
    } catch (e) {
      debugPrint('SyncManager._refreshUnsyncedCount failed: $e');
    }
  }

  void _initPolling() {
    _pollTimer = Timer.periodic(const Duration(minutes: 2), (_) => _trySync());
  }

  int getUnsyncedCount() => _cachedUnsyncedCount;

  Future<void> _trySync() async {
    print('SYNC _trySync ENTER');
    debugPrint('========== SYNC ENTER _trySync ==========');
    if (kIsWeb) {
      debugPrint('SYNC EXIT _trySync: kIsWeb');
      return;
    }
    debugPrint('SYNC _trySync: connectivity=${_connectivityService.currentStatus}');
    if (!_connectivityService.currentStatus) {
      debugPrint('SYNC EXIT _trySync: no connectivity');
      return;
    }
    debugPrint('SYNC _trySync: syncState=$_syncState');
    if (_syncState == SyncState.syncing) {
      debugPrint('SYNC EXIT _trySync: already syncing');
      return;
    }

    _syncState = SyncState.syncing;
    notifyListeners();

    try {
      // 1. Sync with Flask API
      debugPrint('SYNC ENTER _syncWithFlask');
      await _syncWithFlask();
      debugPrint('SYNC EXIT _syncWithFlask (success)');

      // 2. Also backup to Google Drive if signed in
      if (!_isSignedIn) {
        _isSignedIn = await _authService.isSignedIn();
      }
      if (_isSignedIn) {
        try {
          await _driveService.syncPendingRecords();
        } catch (e) {
          debugPrint('Auto-sync: Drive sync failed: $e');
        }
      }

      _syncState = SyncState.synced;
      notifyListeners();
      debugPrint('========== SYNC COMPLETE ==========');
    } catch (e) {
      debugPrint('SyncManager._trySync failed: $e');
      debugPrint('========== SYNC ERROR ==========');
      _syncState = SyncState.error;
      notifyListeners();
    }
  }

  // ─── ID Conversion Helpers ──────────────────────────

  int _toSqlitePatientId(String hiveId) =>
      int.tryParse(hiveId.replaceAll(RegExp(r'^P0*'), '')) ?? 0;

  String _patientToStringId(int sqliteId) =>
      'P${sqliteId.toString().padLeft(3, '0')}';

  int _toSqliteOpdId(String hiveId) =>
      int.tryParse(hiveId.replaceAll(RegExp(r'^R0*'), '')) ?? 0;

  String _opdToStringId(int sqliteId) => 'R$sqliteId';

  // ─── Push Data Builders ────────────────────────────

  Map<String, dynamic> _patientRowToPushMap(Map<String, dynamic> row) {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    return {
      'id': _patientToStringId(row['id'] as int),
      'name': row['full_name'],
      'dob': row['dob'] ?? '',
      'age': row['age'] ?? 0,
      'gender': row['gender'] ?? 'Not Specified',
      'blood_group': row['blood_group'] ?? 'Not Specified',
      'mobile': row['mobile_number'],
      'address': row['address'] ?? '',
      'created_at': createdDt.toIso8601String(),
      'updated_at': createdDt.toIso8601String(),
      'is_synced': 1,
    };
  }

  Map<String, dynamic> _opdRowToPushMap(Map<String, dynamic> row) {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    final visitDt = row['visit_datetime'] as String? ?? '';
    return {
      'id': row['opd_id']?.toString() ?? _opdToStringId(row['id'] as int),
      'patient_id': _patientToStringId(row['patient_id'] as int),
      'type': row['opd_type'] ?? 'consultation',
      'symptoms': row['symptoms'] ?? '',
      'diagnosis': row['diagnosis'] ?? '',
      'medicines': row['medicines'] ?? '',
      'visit_date': DateTime.tryParse(visitDt)?.toIso8601String() ?? createdDt.toIso8601String(),
      'clinical_notes': row['clinical_notes'] ?? '',
      'consultation_fee': (row['consultation_fee'] as num?)?.toString() ?? '',
      'medicine_fee': (row['medicine_fee'] as num?)?.toString() ?? '',
      'discount': '',
      'payment_mode': row['payment_mode'] ?? '',
      'charge_type': row['charge_type'] ?? '',
      'previous_visit_date': '',
      'follow_up_reason': '',
      'next_visit': row['next_visit_date'] ?? '',
      'blood_group': '',
      'created_at': createdDt.toIso8601String(),
      'updated_at': createdDt.toIso8601String(),
      'is_synced': 1,
    };
  }

  // ─── Pull Data Writers ─────────────────────────────

  Map<String, dynamic> _remotePatientToRow(Map<String, dynamic> remote, int sqliteId) {
    return {
      'id': sqliteId,
      'full_name': remote['name']?.toString() ?? '',
      'mobile_number': remote['mobile']?.toString() ?? '',
      'alternate_mobile': null,
      'gender': remote['gender']?.toString() ?? 'Not Specified',
      'dob': remote['dob']?.toString() ?? '',
      'age': int.tryParse(remote['age']?.toString() ?? '') ?? 0,
      'blood_group': remote['blood_group']?.toString() ?? 'Not Specified',
      'address': remote['address']?.toString() ?? '',
      'created_at': remote['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _remoteOpdToRow(Map<String, dynamic> remote, int sqliteId) {
    return {
      'id': sqliteId,
      'opd_id': remote['id']?.toString() ?? '',
      'patient_id': _toSqlitePatientId(remote['patient_id']?.toString() ?? ''),
      'visit_datetime': remote['visit_date']?.toString() ?? '',
      'opd_type': remote['type']?.toString() ?? 'consultation',
      'charge_type': remote['charge_type']?.toString() ?? '',
      'diagnosis': remote['diagnosis']?.toString() ?? '',
      'symptoms': remote['symptoms']?.toString() ?? '',
      'clinical_notes': remote['clinical_notes']?.toString() ?? '',
      'consultation_fee': double.tryParse(remote['consultation_fee']?.toString() ?? '') ?? 0.0,
      'medicine_fee': double.tryParse(remote['medicine_fee']?.toString() ?? '') ?? 0.0,
      'payment_mode': remote['payment_mode']?.toString() ?? '',
      'next_visit_date': remote['next_visit']?.toString() ?? '',
      'created_at': remote['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      'medicines': remote['medicines']?.toString() ?? '',
    };
  }

  // ─── Sync Logic ────────────────────────────────────

  Future<void> _syncWithFlask() async {
    print('SYNC _syncWithFlask ENTER');
    debugPrint('SYNC _syncWithFlask ENTER');
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString('last_flask_sync') ?? '';
    debugPrint('SYNC lastSync=$lastSync');

    // ── Push (sync_queue driven) ─────────────────────

    final pushPatients = <Map<String, dynamic>>[];
    final pushOpd = <Map<String, dynamic>>[];
    final pushAppts = <Map<String, dynamic>>[];
    final syncedApptModels = <AppointmentModel>[];

    final pendingEntries = await _syncQueueRepo.getPending();
    debugPrint('SYNC pendingEntries count=${pendingEntries.length}');
    final processedPatientIds = <String>{};
    final processedOpdIds = <String>{};

    for (final entry in pendingEntries) {
      final entityType = entry['entity_type'] as String? ?? '';
      final entityId = entry['entity_id'] as String? ?? '';
      debugPrint('SYNC processing entry type=$entityType id=$entityId');

      if (entityType == 'patient' && !processedPatientIds.contains(entityId)) {
        processedPatientIds.add(entityId);
        final sqliteId = _toSqlitePatientId(entityId);
        try {
          final row = await _patientRepo.getById(sqliteId);
          if (row != null) {
            pushPatients.add(_patientRowToPushMap(row));
            debugPrint('SYNC added patient $entityId to push');
          } else {
            debugPrint('SYNC patient row null for $entityId (sqliteId=$sqliteId)');
          }
        } catch (e) {
          debugPrint('SYNC patient fetch error for $entityId: $e');
        }
      } else if (entityType == 'opd_visit' &&
           !processedOpdIds.contains(entityId)) {
        processedOpdIds.add(entityId);

        final row = await _opdRepo.getByOpdId(entityId);

        if (row != null) {
          debugPrint('SYNC FOUND OPD: $entityId');
          pushOpd.add(_opdRowToPushMap(row));
        } else {
          debugPrint('SYNC OPD NOT FOUND: $entityId');
        }
      }
    }

    try {
      final apptBox = Hive.box<AppointmentModel>('appointments');
      for (final a in apptBox.values) {
        if (!a.isSynced) {
          pushAppts.add(a.toJson());
          syncedApptModels.add(a);
        }
      }
    } catch (_) {}

    debugPrint('SYNC pushPatients=${pushPatients.length} pushOpd=${pushOpd.length} pushAppts=${pushAppts.length} pendingEntries=${pendingEntries.length}');
    if (pushPatients.isNotEmpty || pushOpd.isNotEmpty || pushAppts.isNotEmpty) {
      try {
        debugPrint('SYNC CALLING API SYNC PUSH');
        await ApiService.syncPush(
          patients: pushPatients,
          opdRecords: pushOpd,
          appointments: pushAppts,
        );
        debugPrint('SYNC API SYNC PUSH SUCCESS');

        // Mark queue entries as synced
        final now = DateTime.now();
        for (final entry in pendingEntries) {
          await _syncQueueRepo.update(entry['id'] as int, {
            'status': 'synced',
            'last_attempt': now.toIso8601String(),
          });
        }
        debugPrint('SYNC marked ${pendingEntries.length} queue entries synced');

        // Mark Hive appointments as synced
        for (final a in syncedApptModels) {
          try {
            final box = Hive.box<AppointmentModel>('appointments');
            box.put(a.id, a.copyWith(isSynced: true, updatedAt: now));
          } catch (_) {}
        }
        debugPrint('SYNC marked ${syncedApptModels.length} appointments synced');
      } catch (e) {
        debugPrint('SYNC PUSH FAILED: $e');
        // Mark entries as failed or exhausted
        for (final entry in pendingEntries) {
          final retryCount = (entry['retry_count'] as int? ?? 0) + 1;
          final status = retryCount >= 5 ? 'failed' : 'pending';
          await _syncQueueRepo.update(entry['id'] as int, {
            'retry_count': retryCount,
            'status': status,
            'last_error': e.toString(),
            'last_attempt': DateTime.now().toIso8601String(),
          });
        }
        debugPrint('SYNC rethrowing after marking ${pendingEntries.length} entries');
        rethrow;
      }
    } else if (pendingEntries.isNotEmpty) {
      debugPrint('SYNC no pushable data — closing ${pendingEntries.length} entries');
      // No pushable data (all entities deleted) — close entries
      for (final entry in pendingEntries) {
        await _syncQueueRepo.update(entry['id'] as int, {
          'status': 'synced',
          'last_attempt': DateTime.now().toIso8601String(),
        });
      }
    } else {
      debugPrint('SYNC nothing to push, no pending entries');
    }

    // ── Include OPDs with pending images from previous failed uploads ──
    {
      final docBox = Hive.box('opd_documents');
      for (final key in docBox.keys) {
        processedOpdIds.add(key.toString());
      }
    }

    // ── Upload images for pushed OPDs ────────────────
    for (final opdId in processedOpdIds) {
      try {
        final row = await _opdRepo.getByOpdId(opdId);
        if (row == null) {
          final docBox = Hive.box('opd_documents');
          if (docBox.containsKey(opdId)) {
            print('SYNC cleanup: OPD $opdId not in local DB, removing stale Hive entry');
            await docBox.delete(opdId);
          }
          continue;
        }
        final sqliteId = row['id'] as int;

        final pendingImages =
            await _patientImagesRepo.getPendingByOpdVisitId(sqliteId);

        if (pendingImages.isNotEmpty) {
          final files = <File>[];
          for (final img in pendingImages) {
            final path = img['file_path'] as String;
            final file = File(path);
            if (await file.exists()) files.add(file);
          }
          if (files.isNotEmpty) {
            await ApiService.pushImages(opdId, files);
            await _patientImagesRepo.markSyncedByOpdVisitId(sqliteId);
            _imageUploadRetries.remove(opdId);
            print('SYNC image uploaded for OPD $opdId (from patient_images)');
          }
        } else {
          final docBox = Hive.box('opd_documents');
          final raw = docBox.get(opdId);
          if (raw != null) {
            final bytes = base64Decode(raw.toString());
            final tempFile = File(
              '${Directory.systemTemp.path}/${opdId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
            );
            try {
              await tempFile.writeAsBytes(bytes);
              await ApiService.pushImages(opdId, [tempFile]);
              await docBox.delete(opdId);
              _imageUploadRetries.remove(opdId);
              print('SYNC image uploaded for OPD $opdId (from opd_documents Hive)');
            } catch (e) {
              if (e is ApiException && e.statusCode == 404) {
                print('SYNC OPD $opdId not found on Flask, removing stale Hive entry');
                await docBox.delete(opdId);
              }
              rethrow;
            } finally {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            }
          } else {
            print('SYNC no Hive entry for OPD $opdId in image loop');
          }
        }
      } catch (e, st) {
        print('SYNC image upload failed for OPD $opdId: $e');
        print(st);
        final retries = (_imageUploadRetries[opdId] ?? 0) + 1;
        _imageUploadRetries[opdId] = retries;
        if (retries >= 3) {
          print('SYNC giving up on OPD $opdId image after $retries failures');
          final docBox = Hive.box('opd_documents');
          if (docBox.containsKey(opdId)) {
            await docBox.delete(opdId);
            print('SYNC removed stale Hive entry for OPD $opdId');
          }
          _imageUploadRetries.remove(opdId);
        }
      }
    }

    // ── Pull ─────────────────────────────────────────
    debugPrint('SYNC PULL START (lastSync=$lastSync)');

    try {
      final data = await ApiService.syncPull(lastSync);
      debugPrint('SYNC PULL SUCCESS');

      final remotePatients = data['patients'] as List<dynamic>? ?? [];
      final remoteOpd = data['opd_records'] as List<dynamic>? ?? [];
      final remoteAppts = data['appointments'] as List<dynamic>? ?? [];

      for (final json in remotePatients) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final remoteId = map['id']?.toString() ?? '';
          final sqliteId = _toSqlitePatientId(remoteId);
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');

          final existing = await _patientRepo.getById(sqliteId);
          final localCreatedAt = DateTime.tryParse(
            existing?['created_at'] as String? ?? '',
          );

          if (existing == null ||
              (remoteUpdatedAt != null && localCreatedAt != null && remoteUpdatedAt.isAfter(localCreatedAt))) {
            if (existing != null) {
              await _patientRepo.update(sqliteId, _remotePatientToRow(map, sqliteId));
            } else {
              await _patientRepo.insert(_remotePatientToRow(map, sqliteId));
            }
          }
        } catch (_) {}
      }

      for (final json in remoteOpd) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final remoteId = map['id']?.toString() ?? '';
          final sqliteId = _toSqliteOpdId(remoteId);
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');

          final existing = await _opdRepo.getById(sqliteId);
          final localCreatedAt = DateTime.tryParse(
            existing?['created_at'] as String? ?? '',
          );

          if (existing == null ||
              (remoteUpdatedAt != null && localCreatedAt != null && remoteUpdatedAt.isAfter(localCreatedAt))) {
            final row = _remoteOpdToRow(map, sqliteId);
            if (existing != null) {
              await _opdRepo.update(sqliteId, row);
            } else {
              await _opdRepo.insert(row);
            }
          }
        } catch (_) {}
      }

      for (final json in remoteAppts) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final apptBox = Hive.box<AppointmentModel>('appointments');
          final existing = apptBox.get(map['id']);
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');
          if (existing == null ||
              (remoteUpdatedAt != null && existing.updatedAt.isBefore(remoteUpdatedAt))) {
            apptBox.put(map['id'], AppointmentModel.fromJson(map));
          }
        } catch (_) {}
      }

      await prefs.setString(
        'last_flask_sync',
        data['server_time']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Pull might fail — push already succeeded
    }
  }

  Future<void> forceSyncNow() async {
    print('FORCE SYNC START');
    await _trySync();
    print('FORCE SYNC END');
  }

  Future<bool> triggerManualSync() async {
    if (kIsWeb) return false;
    if (_syncState == SyncState.syncing) return false;

    _syncState = SyncState.syncing;
    notifyListeners();

    try {
      await _syncWithFlask();
    } catch (_) {}

    bool driveOk = false;
    if (!_isSignedIn) {
      _isSignedIn = await _authService.isSignedIn();
    }
    if (_isSignedIn) {
      try {
        await _driveService.syncPendingRecords();
        driveOk = true;
      } catch (_) {}
    } else {
      driveOk = true;
    }

    _syncState = SyncState.synced;
    notifyListeners();

    if (driveOk) {
      await EventNotificationService.notifySyncComplete(
        recordCount: getUnsyncedCount(),
      );
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: const Text('✓ Data synced'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  }

  Future<bool> backupToDriveOnly() async {
    if (kIsWeb) return false;
    if (_syncState == SyncState.syncing) return false;

    _syncState = SyncState.syncing;
    notifyListeners();

    try {
      if (!_isSignedIn) {
        _isSignedIn = await _authService.isSignedIn();
      }
      if (!_isSignedIn) {
        _syncState = SyncState.error;
        notifyListeners();
        return false;
      }
      await _driveService.syncPendingRecords();
      _syncState = SyncState.synced;
      notifyListeners();
      await EventNotificationService.notifyBackupComplete(success: true);
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: const Text('✓ Backed up to Google Drive'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } catch (e) {
      _syncState = SyncState.error;
      notifyListeners();
      await EventNotificationService.notifyBackupComplete(
        success: false,
        details: 'Backup failed: $e',
      );
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('✗ Backup failed: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  Duration calculateInitialDelay(TimeOfDay scheduledTime) {
    final now = DateTime.now();
    var scheduledDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      scheduledTime.hour,
      scheduledTime.minute,
    );
    if (scheduledDateTime.isBefore(now)) {
      scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
    }
    return scheduledDateTime.difference(now);
  }

  Future<void> scheduleDailyBackup(TimeOfDay time) async {
    if (kIsWeb) return;
    try {
      await scheduleDailyBackupTask(time);
    } catch (e) {
      debugPrint('scheduleDailyBackup error: $e');
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _googleAuthSub?.cancel();
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}
