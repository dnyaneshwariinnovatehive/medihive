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
import 'background_backup_handler.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../repositories/patient_images_repository.dart';
import '../repositories/calendar_notes_repository.dart';
import '../repositories/clinic_settings_repository.dart';
import '../repositories/medicines_repository.dart';
import '../repositories/symptoms_master_repository.dart';
import 'local_notification_service.dart';
import '../database/database_helper.dart';
import '../utils/helpers.dart';

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
  bool _pendingSyncRequested = false;
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
  final CalendarNotesRepository _calendarNotesRepo = _tryInit('CalendarNotesRepository', () => CalendarNotesRepository());
  final ClinicSettingsRepository _clinicSettingsRepo = _tryInit('ClinicSettingsRepository', () => ClinicSettingsRepository());
  final MedicinesRepository _medicinesRepo = _tryInit('MedicinesRepository', () => MedicinesRepository());
  final SymptomsMasterRepository _symptomsRepo = _tryInit('SymptomsMasterRepository', () => SymptomsMasterRepository());
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

    // ── Ensure we have a valid API token ────────────────
    // If the token is missing (e.g. app started in offline/local-auth mode),
    // try to re-login so sync push/pull don't fail with 401.
    try {
      await ApiService.ensureToken();
    } catch (e) {
      debugPrint('SYNC token check failed: $e');
    }

    try {
      // 1. Sync with Flask API
      debugPrint('SYNC ENTER _syncWithFlask');
      await _syncWithFlask();
      debugPrint('SYNC EXIT _syncWithFlask (success)');

      // NOTE: Excel backup (.xlsx files) is intentionally NOT called here.
      // The Flask API push (above) writes OPD data directly to the existing
      // Google Sheet. Images are uploaded to the existing "MediHive Images"
      // Drive folder. Creating .xlsx backup files during sync is disabled
      // to prevent duplicate file creation in Google Drive.
      // Use backupToDriveOnly() for manual Excel backups.

      _syncState = SyncState.synced;
      notifyListeners();

      // If a forceSyncNow was requested while we were syncing, run again
      if (_pendingSyncRequested) {
        _pendingSyncRequested = false;
        debugPrint('SYNC running deferred sync from pendingSyncRequested');
        _trySync(); // fire-and-forget to avoid deep recursion
      }

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

  String _opdToStringId(int sqliteId) => 'R$sqliteId';

  // ─── Push Data Builders ────────────────────────────

  String _resolveUpdatedAt(Map<String, dynamic> row) {
    final updatedAt = row['updated_at'] as String?;
    if (updatedAt != null && updatedAt.isNotEmpty) return updatedAt;
    final createdAt = row['created_at'] as String?;
    if (createdAt != null && createdAt.isNotEmpty) return createdAt;
    return DateTime.now().toIso8601String();
  }

  Future<String> _patientSyncId(Map<String, dynamic> row) async {
    final syncId = row['sync_id'] as String?;
    if (syncId != null && syncId.isNotEmpty) return syncId;
    return _patientToStringId(Helpers.toInt(row['id']));
  }

  Future<Map<String, dynamic>> _patientRowToPushMap(Map<String, dynamic> row) async {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    return {
      'id': await _patientSyncId(row),
      'full_name': row['full_name'],
      'dob': row['dob'] ?? '',
      'age': row['age'] ?? 0,
      'gender': row['gender'] ?? 'Not Specified',
      'blood_group': row['blood_group'] ?? 'Not Specified',
      'mobile_number': row['mobile_number'],
      'alternate_mobile': row['alternate_mobile'],
      'address': row['address'] ?? '',
      'created_at': createdDt.toIso8601String(),
      'updated_at': _resolveUpdatedAt(row),
      'is_synced': 1,
    };
  }

  Future<Map<String, dynamic>> _opdRowToPushMap(Map<String, dynamic> row) async {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    final visitDt = row['visit_datetime'] as String? ?? '';
    final localPatientId = Helpers.toInt(row['patient_id']);
    String patientSyncId;
    String patientBloodGroup = '';
    try {
      final patient = await _patientRepo.getById(localPatientId);
      patientSyncId = patient?['sync_id'] as String? ?? _patientToStringId(localPatientId);
      patientBloodGroup = patient?['blood_group'] as String? ?? '';
    } catch (_) {
      patientSyncId = _patientToStringId(localPatientId);
    }
    final pkNotes = row['panchakarma_notes'] ?? '';
    print('SYNC DEBUG: _opdRowToPushMap panchakarma_notes="${pkNotes}"');
    return {
      'id': row['opd_id']?.toString() ?? _opdToStringId(Helpers.toInt(row['id'])),
      'patient_id': patientSyncId,
      'opd_type': row['opd_type'] ?? 'consultation',
      'symptoms': row['symptoms'] ?? '',
      'diagnosis': row['diagnosis'] ?? '',
      'medicines': row['medicines'] ?? '',
      'visit_datetime': DateTime.tryParse(visitDt)?.toIso8601String() ?? createdDt.toIso8601String(),
      'clinical_notes': row['clinical_notes'] ?? '',
      'panchakarma_notes': pkNotes,
      'consultation_fee': row['consultation_fee']?.toString() ?? '',
      'medicine_fee': row['medicine_fee']?.toString() ?? '',
      'panchakarma_fee': row['panchakarma_fee']?.toString() ?? '',
      'total_fee': row['total_fee']?.toString() ?? '',
      'discount_value': row['discount_value']?.toString() ?? '',
      'discount_type': row['discount_type'] ?? '',
      'payment_mode': row['payment_mode'] ?? '',
      'charge_type': row['charge_type'] ?? '',
      'previous_visit_date': '',
      'followup_status': row['followup_status'] ?? '',
      'next_visit_date': row['next_visit_date'] ?? '',
      'blood_group': patientBloodGroup,
      'created_at': createdDt.toIso8601String(),
      'updated_at': _resolveUpdatedAt(row),
      'is_synced': 1,
    };
  }

  // ─── Pull Data Writers ─────────────────────────────

  Map<String, dynamic> _remotePatientToRow(Map<String, dynamic> remote, int sqliteId, String syncId) {
    return {
      'id': sqliteId,
      'sync_id': syncId,
      'full_name': remote['full_name']?.toString() ?? '',
      'mobile_number': remote['mobile_number']?.toString() ?? '',
      'alternate_mobile': remote['alternate_mobile']?.toString(),
      'gender': remote['gender']?.toString() ?? 'Not Specified',
      'dob': remote['dob']?.toString() ?? '',
      'age': int.tryParse(remote['age']?.toString() ?? '') ?? 0,
      'blood_group': remote['blood_group']?.toString() ?? 'Not Specified',
      'address': remote['address']?.toString() ?? '',
      'created_at': remote['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      'updated_at': remote['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _remoteOpdToRow(Map<String, dynamic> remote, int sqliteId) async {
    final remotePatientId = remote['patient_id']?.toString() ?? '';
    int localPatientId;
    try {
      final patient = await _patientRepo.getBySyncId(remotePatientId);
      localPatientId = Helpers.toInt(patient?['id'], _toSqlitePatientId(remotePatientId));
    } catch (_) {
      localPatientId = _toSqlitePatientId(remotePatientId);
    }
    return {
      'id': sqliteId,
      'opd_id': remote['id']?.toString() ?? '',
      'patient_id': localPatientId,
      'visit_datetime': remote['visit_datetime']?.toString() ?? '',
      'opd_type': remote['opd_type']?.toString() ?? 'consultation',
      'charge_type': remote['charge_type']?.toString() ?? '',
      'diagnosis': remote['diagnosis']?.toString() ?? '',
      'symptoms': remote['symptoms']?.toString() ?? '',
      'clinical_notes': remote['clinical_notes']?.toString() ?? '',
      'panchakarma_notes': remote['panchakarma_notes']?.toString() ?? '',
      'consultation_fee': double.tryParse(remote['consultation_fee']?.toString() ?? '') ?? 0.0,
      'medicine_fee': double.tryParse(remote['medicine_fee']?.toString() ?? '') ?? 0.0,
      'payment_mode': remote['payment_mode']?.toString() ?? '',
      'next_visit_date': remote['next_visit_date']?.toString() ?? '',
      'followup_status': remote['followup_status']?.toString() ?? '',
      'discount_value': double.tryParse(remote['discount_value']?.toString() ?? '') ?? 0.0,
      'created_at': remote['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      'updated_at': remote['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
      'medicines': remote['medicines']?.toString() ?? '',
    };
  }

  // ─── Sync Logic ────────────────────────────────────

  Future<void> _syncWithFlask() async {
    print('SYNC _syncWithFlask ENTER');
    debugPrint('SYNC _syncWithFlask ENTER');

    // Ensure we have a valid API token before attempting sync.
    // This handles cases where the app started in local-auth mode
    // without a JWT token.
    try {
      await ApiService.ensureToken();
    } catch (e) {
      debugPrint('SYNC _syncWithFlask: token acquisition failed: $e');
    }

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
    final deletedEntities = <Map<String, String>>[];

    for (final entry in pendingEntries) {
      final entityType = entry['entity_type'] as String? ?? '';
      final entityId = entry['entity_id'] as String? ?? '';
      final operation = entry['operation'] as String? ?? 'upsert';
      debugPrint('SYNC processing entry type=$entityType id=$entityId operation=$operation');

      if (operation == 'delete') {
        deletedEntities.add({'entity_type': entityType, 'entity_id': entityId});
        continue;
      }

      if (entityType == 'patient' && !processedPatientIds.contains(entityId)) {
        processedPatientIds.add(entityId);
        try {
          final row = await _patientRepo.getBySyncId(entityId);
          if (row != null) {
            pushPatients.add(await _patientRowToPushMap(row));
            debugPrint('SYNC added patient $entityId to push');
          } else {
            debugPrint('SYNC patient row null for $entityId');
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
          pushOpd.add(await _opdRowToPushMap(row));
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

    // ── Build push data for new sync tables ─────────────────
    final pushCalendarNotes = <Map<String, dynamic>>[];
    final pushClinicSettings = <Map<String, dynamic>>[];
    final pushMedicines = <Map<String, dynamic>>[];
    final pushSymptoms = <Map<String, dynamic>>[];

    // Always send all calendar_notes, clinic_settings, medicines, symptoms
    // for full sync (these are small reference/singleton tables)
    try {
      final allNotes = await _calendarNotesRepo.getAll();
      for (final note in allNotes) {
        pushCalendarNotes.add(Map<String, dynamic>.from(note));
      }
    } catch (e) {
      debugPrint('SYNC: error reading calendar_notes: $e');
    }

    try {
      final settings = await _clinicSettingsRepo.getFirst();
      if (settings != null) {
        pushClinicSettings.add(Map<String, dynamic>.from(settings));
      }
    } catch (e) {
      debugPrint('SYNC: error reading clinic_settings: $e');
    }

    try {
      final allMeds = await _medicinesRepo.getAll();
      for (final med in allMeds) {
        pushMedicines.add(Map<String, dynamic>.from(med));
      }
    } catch (e) {
      debugPrint('SYNC: error reading medicines: $e');
    }

    try {
      final allSyms = await _symptomsRepo.getAll();
      for (final sym in allSyms) {
        pushSymptoms.add(Map<String, dynamic>.from(sym));
      }
    } catch (e) {
      debugPrint('SYNC: error reading symptoms: $e');
    }

    debugPrint('SYNC pushPatients=${pushPatients.length} pushOpd=${pushOpd.length} pushAppts=${pushAppts.length} pendingEntries=${pendingEntries.length}');
    if (pushOpd.isNotEmpty) {
      for (final opd in pushOpd) {
        debugPrint('SYNC PUSH OPD: id=${opd['id']} patient_id=${opd['patient_id']} '
            'diagnosis=${opd['diagnosis']} symptoms=${opd['symptoms']} '
            'clinical_notes=${opd['clinical_notes']} panchakarma_notes=${opd['panchakarma_notes']} '
            'consultation_fee=${opd['consultation_fee']} medicine_fee=${opd['medicine_fee']} '
            'panchakarma_fee=${opd['panchakarma_fee']} total_fee=${opd['total_fee']} '
            'discount_value=${opd['discount_value']} discount_type=${opd['discount_type']} '
            'payment_mode=${opd['payment_mode']} followup_status=${opd['followup_status']} '
            'next_visit_date=${opd['next_visit_date']} visit_datetime=${opd['visit_datetime']}');
      }
    }
    if (pushPatients.isNotEmpty || pushOpd.isNotEmpty || pushAppts.isNotEmpty || pushCalendarNotes.isNotEmpty || pushClinicSettings.isNotEmpty || pushMedicines.isNotEmpty || pushSymptoms.isNotEmpty) {
      try {
        debugPrint('SYNC CALLING API SYNC PUSH');
        final pushResponse = await ApiService.syncPush(
          patients: pushPatients,
          opdRecords: pushOpd,
          appointments: pushAppts,
          deletedEntities: deletedEntities,
          calendarNotes: pushCalendarNotes,
          clinicSettings: pushClinicSettings,
          medicines: pushMedicines,
          symptoms: pushSymptoms,
        );
        debugPrint('SYNC API SYNC PUSH SUCCESS');

        // ── Check for sheet warnings (207 Multi-Status) ──────────
        // When the backend saves data locally but fails to write to
        // Google Sheets, it returns sheet_warnings. Entries should NOT
        // be marked synced — the outer catch will increment retry_count
        // and leave them as 'pending' for retry on next sync cycle.
        final sheetWarnings = pushResponse['sheet_warnings'] as List<dynamic>?;
        if (sheetWarnings != null && sheetWarnings.isNotEmpty) {
          debugPrint('SYNC SHEET WARNINGS DETECTED: $sheetWarnings');
          throw ApiException(
            207,
            'Data saved on server but Google Sheet was not updated. '
            'Sheet warnings: ${sheetWarnings.join("; ")}. '
            'Verify the service account has Editor access.',
          );
        }

        // Process temp ID mappings from server
        final tempMapped = pushResponse['temp_ids_mapped'] as Map<String, dynamic>? ?? {};
        if (tempMapped.isNotEmpty) {
          debugPrint('SYNC processing temp IDs: $tempMapped');
          for (final entry in tempMapped.entries) {
            final tempId = entry.key;
            final realId = entry.value as String;
            await _patientRepo.updateSyncId(tempId, realId);
          }
          debugPrint('SYNC temp IDs updated');
        }

        // Mark queue entries as synced
        final now = DateTime.now();
        for (final entry in pendingEntries) {
          await _syncQueueRepo.update(Helpers.toInt(entry['id']), {
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
          await _syncQueueRepo.update(Helpers.toInt(entry['id']), {
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
        await _syncQueueRepo.update(Helpers.toInt(entry['id']), {
          'status': 'synced',
          'last_attempt': DateTime.now().toIso8601String(),
        });
      }
    } else {
      debugPrint('SYNC nothing to push, no pending entries');
    }

    // ── Include OPDs with pending images from SQLite patient_images ──
    try {
      final pendingOpdVids = await _patientImagesRepo.getDistinctOpdVisitIdsWithPending();
      print('IMAGES: found ${pendingOpdVids.length} OPD visit IDs with pending SQLite images');
      for (final vid in pendingOpdVids) {
        final row = await _opdRepo.getById(vid);
        if (row != null) {
          final opdId = row['opd_id']?.toString() ?? '';
          processedOpdIds.add(opdId);
          print('IMAGES: added OPD $opdId from SQLite patient_images (visit_id=$vid)');
        }
      }
    } catch (e) {
      print('IMAGES: error reading SQLite patient_images: $e');
    }

    // ── Include OPDs with pending images from previous failed uploads ──
    {
      final docBox = Hive.box('opd_documents');
      final keys = docBox.keys.toList();
      print('IMAGES: found ${keys.length} entries in Hive opd_documents box');
      for (final key in keys) {
        processedOpdIds.add(key.toString());
        print('IMAGES: added OPD $key from Hive opd_documents');
      }
    }

    print('IMAGES: total OPDs to process for image upload: ${processedOpdIds.length}');
    print('IMAGES: OPD IDs: $processedOpdIds');

    // ── Upload images for pushed OPDs ────────────────
    for (final opdId in processedOpdIds) {
      try {
        print('IMAGES: processing OPD $opdId');
        final row = await _opdRepo.getByOpdId(opdId);
        if (row == null) {
          print('IMAGES: OPD $opdId not found in local DB');
          final docBox = Hive.box('opd_documents');
          if (docBox.containsKey(opdId)) {
            print('IMAGES: cleanup - removing stale Hive entry for OPD $opdId');
            await docBox.delete(opdId);
          }
          continue;
        }
        final sqliteId = Helpers.toInt(row['id']);
        print('IMAGES: OPD $opdId found in local DB (sqlite_id=$sqliteId)');

        final pendingImages =
            await _patientImagesRepo.getPendingByOpdVisitId(sqliteId);
        print('IMAGES: pending SQLite images for OPD $opdId: ${pendingImages.length}');

        if (pendingImages.isNotEmpty) {
          // ── PATH A: Upload from SQLite patient_images ──
          final files = <File>[];
          for (final img in pendingImages) {
            final path = img['file_path'] as String;
            final file = File(path);
            final exists = await file.exists();
            print('IMAGES: SQLite image path=$path exists=$exists');
            if (exists) files.add(file);
          }
          if (files.isNotEmpty) {
            print('IMAGES: PATH A - uploading ${files.length} file(s) from SQLite for OPD $opdId');
            await ApiService.pushImages(opdId, files);
            await _patientImagesRepo.markSyncedByOpdVisitId(sqliteId);
            _imageUploadRetries.remove(opdId);
            print('IMAGES: PATH A - upload SUCCESS for OPD $opdId (from patient_images)');
          } else {
            print('IMAGES: PATH A - no valid files found on disk for OPD $opdId');
          }
        } else {
          // ── PATH B: Upload from Hive opd_documents (fallback) ──
          final docBox = Hive.box('opd_documents');
          final raw = docBox.get(opdId);
          final hasHiveEntry = raw != null;
          print('IMAGES: PATH B - checking Hive opd_documents for OPD $opdId: found=$hasHiveEntry');
          if (raw != null) {
            final rawStr = raw.toString();
            print('IMAGES: PATH B - Hive value type=${raw.runtimeType} length=${rawStr.length}');
            final bytes = base64Decode(rawStr);
            print('IMAGES: PATH B - decoded base64: ${bytes.length} bytes');
            final tempFile = File(
              '${Directory.systemTemp.path}/${opdId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
            );
            try {
              await tempFile.writeAsBytes(bytes);
              print('IMAGES: PATH B - temp file written: ${tempFile.path} (${bytes.length} bytes)');
              print('IMAGES: PATH B - calling ApiService.pushImages for OPD $opdId');
              await ApiService.pushImages(opdId, [tempFile]);
              await docBox.delete(opdId);
              _imageUploadRetries.remove(opdId);
              print('IMAGES: PATH B - upload SUCCESS for OPD $opdId (from opd_documents Hive)');
            } catch (e) {
              print('IMAGES: PATH B - upload FAILED for OPD $opdId: $e');
              if (e is ApiException && e.statusCode == 404) {
                print('IMAGES: PATH B - OPD $opdId not found on Flask, removing stale Hive entry');
                await docBox.delete(opdId);
              }
              rethrow;
            } finally {
              if (await tempFile.exists()) {
                await tempFile.delete();
                print('IMAGES: PATH B - temp file deleted');
              }
            }
          } else {
            print('IMAGES: PATH B - no Hive entry for OPD $opdId in image loop');
          }
        }
      } catch (e, st) {
        print('IMAGES: ERROR for OPD $opdId: $e');
        print('IMAGES: stack trace: $st');
        final retries = (_imageUploadRetries[opdId] ?? 0) + 1;
        _imageUploadRetries[opdId] = retries;
        print('IMAGES: retry count for OPD $opdId: $retries/3');
        if (retries >= 3) {
          print('IMAGES: giving up on OPD $opdId image after $retries failures — keeping Hive entry for manual retry');
          _imageUploadRetries.remove(opdId);
        }
      }
    }
    // ── Pull ──
    debugPrint('SYNC PULL START (lastSync=$lastSync)');

    final pullSync = lastSync.isEmpty ? '2000-01-01T00:00:00' : lastSync;
    try {
      final data = await ApiService.syncPull(pullSync);
      debugPrint('SYNC PULL SUCCESS');

      final remotePatients = data['patients'] as List<dynamic>? ?? [];
      final remoteOpd = data['opd_records'] as List<dynamic>? ?? [];
      final remoteAppts = data['appointments'] as List<dynamic>? ?? [];
      final remoteCalendarNotes = data['calendar_notes'] as List<dynamic>? ?? [];
      final remoteClinicSettings = data['clinic_settings'] as List<dynamic>? ?? [];
      final remoteMedicines = data['medicines'] as List<dynamic>? ?? [];
      final remoteSymptoms = data['symptoms'] as List<dynamic>? ?? [];
      final remotePatientImages = data['patient_images'] as List<dynamic>? ?? [];

      for (final json in remotePatients) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final remoteId = map['id']?.toString() ?? '';
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');

          final existing = await _patientRepo.getBySyncId(remoteId);
          final localUpdatedAt = DateTime.tryParse(
            existing?['updated_at'] as String? ?? existing?['created_at'] as String? ?? '',
          );

          if (existing == null ||
              (remoteUpdatedAt != null && localUpdatedAt != null && remoteUpdatedAt.isAfter(localUpdatedAt))) {
            if (existing != null) {
              final sqliteId = Helpers.toInt(existing['id']);
              await _patientRepo.update(sqliteId, _remotePatientToRow(map, sqliteId, remoteId));
            } else {
              final maxId = await _patientRepo.getMaxId();
              final newId = maxId + 1;
              await _patientRepo.insert(_remotePatientToRow(map, newId, remoteId));
            }
          }
        } catch (_) {}
      }

      for (final json in remoteOpd) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final remoteId = map['id']?.toString() ?? '';
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');

          final existing = await _opdRepo.getByOpdId(remoteId);
          final localUpdatedAt = DateTime.tryParse(
            existing?['updated_at'] as String? ?? existing?['created_at'] as String? ?? '',
          );

          if (existing == null ||
              (remoteUpdatedAt != null && localUpdatedAt != null && remoteUpdatedAt.isAfter(localUpdatedAt))) {
            final localId = existing != null
                ? Helpers.toInt(existing['id'])
                : (await _opdRepo.getMaxId()) + 1;
            final row = await _remoteOpdToRow(map, localId);
            if (existing != null) {
              await _opdRepo.update(localId, row);
            } else {
              await _opdRepo.insert(row);
            }

            // Ensure follow-up appointment in Hive if next_visit_date is set
            final nextVisit = map['next_visit_date']?.toString() ?? '';
            if (nextVisit.isNotEmpty) {
              final visitDate = DateTime.tryParse(nextVisit);
              if (visitDate != null) {
                try {
                  final apptBox = Hive.box<AppointmentModel>('appointments');
                  final patientId = map['patient_id']?.toString() ?? '';
                  final apptId = 'followup_${remoteId}_$nextVisit';
                  if (!apptBox.containsKey(apptId)) {
                    final appt = AppointmentModel(
                      id: apptId,
                      patientId: patientId,
                      dateTime: visitDate,
                      notes: 'Follow-up',
                      isSynced: true,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    await apptBox.put(apptId, appt);
                    debugPrint('SYNC: created Hive follow-up appointment for OPD $remoteId');

                    // Schedule local OS notification reminder for pulled follow-up
                    if (visitDate.isAfter(DateTime.now())) {
                      LocalNotificationService().scheduleAppointmentReminder(
                        id: apptId,
                        patientName: 'Patient $patientId',
                        appointmentTime: visitDate,
                      );
                    }
                  }
                } catch (_) {}
              }
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
            final appt = AppointmentModel.fromJson(map);
            apptBox.put(map['id'], appt);

            // Schedule local OS notification reminder for pulled appointment
            if (appt.dateTime.isAfter(DateTime.now())) {
              LocalNotificationService().scheduleAppointmentReminder(
                id: appt.id,
                patientName: 'Patient ${appt.patientId}',
                appointmentTime: appt.dateTime,
              );
            }
          }
        } catch (_) {}
      }

      // ── Process calendar_notes (last-write-wins) ──────
      for (final json in remoteCalendarNotes) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final noteDate = map['note_date']?.toString() ?? '';
          if (noteDate.isEmpty) continue;

          final existing = await _calendarNotesRepo.getByDate(noteDate);
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');
          final localUpdatedAt = DateTime.tryParse(
            existing?['updated_at'] as String? ?? existing?['created_at'] as String? ?? '',
          );

          if (existing == null ||
              (remoteUpdatedAt != null && localUpdatedAt != null && remoteUpdatedAt.isAfter(localUpdatedAt))) {
            final row = <String, dynamic>{
              'note_date': noteDate,
              'note_text': map['note_text']?.toString() ?? '',
              'created_at': map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
              'updated_at': map['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
            };
            if (existing != null) {
              await _calendarNotesRepo.updateByDate(noteDate, row);
            } else {
              await _calendarNotesRepo.insert(row);
            }
            debugPrint('SYNC: pulled calendar note for $noteDate');
          }
        } catch (e) {
          debugPrint('SYNC: calendar note pull error: $e');
        }
      }

      // ── Process clinic_settings (singleton, last-write-wins) ──
      for (final json in remoteClinicSettings) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final existing = await _clinicSettingsRepo.getFirst();
          final remoteUpdatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');
          final localUpdatedAt = DateTime.tryParse(
            existing?['updated_at'] as String? ?? existing?['created_at'] as String? ?? '',
          );

          if (existing == null ||
              (remoteUpdatedAt != null && localUpdatedAt != null && remoteUpdatedAt.isAfter(localUpdatedAt))) {
            if (existing != null) {
              await _clinicSettingsRepo.update(Helpers.toInt(existing['id']), map);
            } else {
              await _clinicSettingsRepo.insert(map);
            }
            debugPrint('SYNC: pulled clinic settings');
          }
        } catch (e) {
          debugPrint('SYNC: clinic settings pull error: $e');
        }
      }

      // ── Process medicines (upsert by name) ────────────
      for (final json in remoteMedicines) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final name = map['name']?.toString() ?? '';
          if (name.isEmpty) continue;

          final existing = await _medicinesRepo.getByName(name);
          if (existing == null) {
            await _medicinesRepo.insert({'name': name});
            debugPrint('SYNC: pulled medicine $name');
          }
        } catch (e) {
          debugPrint('SYNC: medicine pull error: $e');
        }
      }

      // ── Process symptoms (upsert by name) ─────────────
      for (final json in remoteSymptoms) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final name = map['name']?.toString() ?? '';
          if (name.isEmpty) continue;

          final existing = await _symptomsRepo.getByName(name);
          if (existing == null) {
            await _symptomsRepo.insert({'name': name});
            debugPrint('SYNC: pulled symptom $name');
          }
        } catch (e) {
          debugPrint('SYNC: symptom pull error: $e');
        }
      }

      // ── Process patient_images ──────────────────────
      for (final json in remotePatientImages) {
        try {
          final map = Map<String, dynamic>.from(json as Map);
          final driveUrl = map['drive_url']?.toString() ?? '';
          final remoteOpdId = map['opd_visit_id']?.toString() ?? '';
          final remotePatientSyncId = map['patient_id']?.toString() ?? '';
          if (driveUrl.isEmpty) continue;

          int localPatientId = 0;
          if (remotePatientSyncId.isNotEmpty) {
            final patient = await _patientRepo.getBySyncId(remotePatientSyncId);
            localPatientId = Helpers.toInt(patient?['id'], _toSqlitePatientId(remotePatientSyncId));
          }

          int localOpdVisitId = 0;
          if (remoteOpdId.isNotEmpty) {
            final opd = await _opdRepo.getByOpdId(remoteOpdId);
            localOpdVisitId = Helpers.toInt(opd?['id']);
          }

          final existingImages = await _patientImagesRepo.getByOpdVisitId(localOpdVisitId);
          final alreadyPresent = existingImages.any(
            (img) => img['drive_url'] == driveUrl || img['file_path'] == driveUrl,
          );

          if (!alreadyPresent && localPatientId > 0) {
            await _patientImagesRepo.insert({
              'patient_id': localPatientId,
              'opd_visit_id': localOpdVisitId > 0 ? localOpdVisitId : null,
              'file_path': driveUrl,
              'image_type': map['image_type']?.toString() ?? 'opd_attachment',
              'sync_status': 'synced',
              'uploaded_at': map['uploaded_at']?.toString() ?? DateTime.now().toIso8601String(),
              'created_at': map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
              'drive_url': driveUrl,
            });
            debugPrint('SYNC: pulled patient image with Drive URL: $driveUrl');
          }
        } catch (e) {
          debugPrint('SYNC: patient image pull error: $e');
        }
      }

      // ── Process deleted entities ──
      final remoteDeleted = data['deleted_entities'] as List<dynamic>? ?? [];
      debugPrint('SYNC processing ${remoteDeleted.length} deleted entities');
      for (final del in remoteDeleted) {
        try {
          final d = Map<String, dynamic>.from(del as Map);
          final etype = d['entity_type']?.toString() ?? '';
          final eid = d['entity_id']?.toString() ?? '';
          debugPrint('SYNC processing delete: type=$etype id=$eid');

          if (etype == 'patient') {
            final local = await _patientRepo.getBySyncId(eid);
            if (local != null) {
              final localId = Helpers.toInt(local['id']);
              final opds = await _opdRepo.getByPatientId(localId);
              for (final opd in opds) {
                final opdSqlId = Helpers.toInt(opd['id']);
                await _patientImagesRepo.deleteByOpdVisitId(opdSqlId);
              }
              await _opdRepo.deleteByPatientId(localId);
              await _patientRepo.delete(localId);
              await _syncQueueRepo.clearByEntity('patient', eid);
              debugPrint('SYNC deleted local patient $eid + OPDs');
            }
          } else if (etype == 'opd_visit') {
            final local = await _opdRepo.getByOpdId(eid);
            if (local != null) {
              final localId = Helpers.toInt(local['id']);
              await _patientImagesRepo.deleteByOpdVisitId(localId);
              await _opdRepo.delete(localId);
              await _syncQueueRepo.clearByEntity('opd_visit', eid);
              debugPrint('SYNC deleted local OPD $eid');
            }
          } else if (etype == 'appointment') {
            try {
              final apptBox = Hive.box<AppointmentModel>('appointments');
              if (apptBox.containsKey(eid)) {
                await apptBox.delete(eid);
                debugPrint('SYNC deleted local appointment $eid');
              }
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('SYNC error processing delete $e');
        }
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
    if (_syncState == SyncState.syncing) {
      debugPrint('FORCE SYNC: already syncing, scheduling deferred sync');
      _pendingSyncRequested = true;
      return;
    }
    await _trySync();
    print('FORCE SYNC END');
  }

  Future<bool> triggerManualSync() async {
    if (kIsWeb) return false;
    if (_syncState == SyncState.syncing) {
      _pendingSyncRequested = true;
      return false;
    }

    _syncState = SyncState.syncing;
    notifyListeners();

    String? errorMessage;
    try {
      await _syncWithFlask();
    } catch (e) {
      errorMessage = e.toString();
      print('MANUAL SYNC ERROR: $e');
    }

    // NOTE: .xlsx file creation is intentionally skipped during manual sync.
    // OPD data was already pushed to Flask API (which writes to the existing
    // Google Sheet). Images are uploaded to the existing "MediHive Images"
    // Drive folder. Use backupToDriveOnly() for manual Excel backups.

    if (errorMessage == null) {
      _syncState = SyncState.synced;
    } else {
      _syncState = SyncState.error;
    }
    notifyListeners();
    return errorMessage == null;
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
      return true;
    } catch (e) {
      _syncState = SyncState.error;
      notifyListeners();
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

  Future<Map<String, dynamic>> clearAllData() async {
    /// Clears ALL data:
    /// 1. Calls backend API to clear Google Sheet + backend SQLite
    /// 2. Clears local SQLite (patients, opd_visits, sync_queue, patient_images, etc.)
    /// 3. Clears Hive boxes (appointments, drafts, opd_documents)
    /// 4. Resets sync-related SharedPreferences
    /// Returns the response from the backend API.
    debugPrint('CLEAR ALL DATA STARTED');

    // 1. Call backend to clear sheet + backend DB
    Map<String, dynamic> apiResponse;
    try {
      apiResponse = await ApiService.clearAllData();
      debugPrint('CLEAR ALL DATA: backend response: $apiResponse');
    } catch (e) {
      debugPrint('CLEAR ALL DATA: backend call failed: $e');
      rethrow;
    }

    // 2. Clear local SQLite tables
    try {
      final db = await DatabaseHelper().database;
      await db.delete('patients');
      await db.delete('opd_visits');
      await db.delete('patient_images');
      await db.delete('sync_queue');
      await db.delete('calendar_notes');
      await db.delete('clinic_settings');
      debugPrint('CLEAR ALL DATA: local SQLite tables cleared');
    } catch (e) {
      debugPrint('CLEAR ALL DATA: local SQLite error: $e');
    }

    // 3. Clear Hive boxes
    try {
      if (Hive.isBoxOpen('appointments')) {
        await Hive.box('appointments').clear();
      }
      if (Hive.isBoxOpen('drafts')) {
        await Hive.box('drafts').clear();
      }
      if (Hive.isBoxOpen('opd_documents')) {
        await Hive.box('opd_documents').clear();
      }
      debugPrint('CLEAR ALL DATA: Hive boxes cleared');
    } catch (e) {
      debugPrint('CLEAR ALL DATA: Hive clear error: $e');
    }

    // 4. Clear sync-related SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_flask_sync');
      await prefs.remove('google_drive_pending_sync');
      await prefs.remove('google_drive_folder_id');
      debugPrint('CLEAR ALL DATA: SharedPreferences reset');
    } catch (e) {
      debugPrint('CLEAR ALL DATA: SharedPreferences error: $e');
    }

    _cachedUnsyncedCount = 0;
    _syncState = SyncState.synced;
    notifyListeners();

    debugPrint('CLEAR ALL DATA COMPLETED');
    return apiResponse;
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