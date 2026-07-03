import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'api_service.dart';
import 'connectivity_service.dart';
import '../models/appointment_model.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';
import '../repositories/cloud_sync_queue_repository.dart';
import '../repositories/device_registration_repository.dart';
import '../repositories/patient_images_repository.dart';
import 'event_notification_service.dart';
import 'local_notification_service.dart';
import 'dart:math';

enum CloudSyncState {
  idle,
  syncing,
  synced,
  error,
  offline,
  notConfigured,
}

class CloudSyncManager extends ChangeNotifier {
  CloudSyncState _state = CloudSyncState.idle;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  String? _deviceId;
  String? _clinicId;
  bool _isRunning = false;
  int _syncCount = 0;
  String _lastError = '';

  final ConnectivityService _connectivity = ConnectivityService();
  final PatientRepository _patientRepo = PatientRepository();
  final OpdRecordRepository _opdRepo = OpdRecordRepository();
  final CloudSyncQueueRepository _cloudQueueRepo = CloudSyncQueueRepository();
  final DeviceRegistrationRepository _deviceRegRepo = DeviceRegistrationRepository();
  final PatientImagesRepository _imagesRepo = PatientImagesRepository();

  static final CloudSyncManager _instance = CloudSyncManager._internal();
  factory CloudSyncManager() => _instance;
  CloudSyncManager._internal();

  CloudSyncState get state => _state;
  bool get isSyncing => _state == CloudSyncState.syncing;
  bool get isConfigured => _cloudBaseUrl.isNotEmpty;
  String get lastError => _lastError;
  int get syncCount => _syncCount;
  String? get deviceId => _deviceId;
  String? get clinicId => _clinicId;

  static String get _cloudBaseUrl =>
      dotenv.env['CLOUD_BASE_URL'] ?? '';
  static String get _localClinicId =>
      dotenv.env['CLINIC_ID'] ?? '';

  /// Start the cloud sync polling loop.
  /// Call once at app startup.
  Future<void> start() async {
    if (_isRunning) return;
    if (!isConfigured) {
      _state = CloudSyncState.notConfigured;
      notifyListeners();
      print('CLOUD SYNC: not configured (CLOUD_BASE_URL not set)');
      return;
    }

    _isRunning = true;
    try {
      _deviceId = await _loadOrCreateDeviceId();
    } catch (e) {
      print('CLOUD SYNC ERROR: _loadOrCreateDeviceId failed: $e');
      _isRunning = false;
      _state = CloudSyncState.error;
      notifyListeners();
      return;
    }
    _clinicId = _localClinicId;

    print('CLOUD SYNC: started device=$_deviceId clinic=$_clinicId');

    // Register device on first run
    await _registerDevice();

    // Start polling every 20 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _syncLoop());

    // Heartbeat every 5 minutes
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) => _sendHeartbeat());

    // Immediate first sync after a short delay
    Timer(const Duration(seconds: 3), () => _syncLoop());

    _state = CloudSyncState.idle;
    notifyListeners();
  }

  /// Stop the cloud sync polling loop.
  void stop() {
    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _state = CloudSyncState.idle;
    notifyListeners();
    debugPrint('CLOUD SYNC: stopped');
  }

  /// Notify that a local change occurred.
  /// Adds an entry to cloud_sync_queue for later upload.
  Future<void> notifyChange({
    required String tableName,
    required String operation,
    required String recordId,
    Map<String, dynamic>? payload,
  }) async {
    if (!_isRunning) return;
    try {
      await _cloudQueueRepo.insert({
        'table_name': tableName,
        'operation': operation,
        'record_id': recordId,
        'payload': payload != null ? jsonEncode(payload) : null,
      });
      debugPrint('CLOUD QUEUE: added $operation $tableName $recordId');
    } catch (e) {
      debugPrint('CLOUD QUEUE: insert failed: $e');
    }
  }

  /// Force an immediate cloud sync.
  Future<void> forceSync() async {
    if (!_isRunning || !isConfigured) return;
    await _syncLoop();
  }

  /// Main sync loop: upload pending + download remote changes.
  Future<void> _syncLoop() async {
    if (_state == CloudSyncState.syncing) return;
    if (!_connectivity.currentStatus) {
      _state = CloudSyncState.offline;
      notifyListeners();
      return;
    }

    _state = CloudSyncState.syncing;
    notifyListeners();

    try {
      if (_deviceId == null) return;
      if (_clinicId == null || _clinicId!.isEmpty) {
        print('CLOUD SYNC: no clinic_id configured');
        _state = CloudSyncState.idle;
        notifyListeners();
        return;
      }

      // Ensure token is available before making API calls
      try {
        await ApiService.ensureToken();
      } catch (_) {}

      // 1. Upload pending changes
      await _uploadChanges();

      // 2. Download remote changes
      await _downloadChanges();

      // 3. Clear synced queue entries
      await _cloudQueueRepo.clearSynced();

      _syncCount++;
      _state = CloudSyncState.synced;
      debugPrint('CLOUD SYNC: cycle $_syncCount complete');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('CLOUD SYNC: error: $e');
      _state = CloudSyncState.error;
    }
    notifyListeners();
  }

  /// Upload all pending cloud_sync_queue entries.
  Future<void> _uploadChanges() async {
    final pending = await _cloudQueueRepo.getPending();
    if (pending.isEmpty) {
      debugPrint('CLOUD UPLOAD: nothing pending');
      return;
    }

    // Group pending entries by table_name to build payloads
    final patients = <Map<String, dynamic>>[];
    final opdRecords = <Map<String, dynamic>>[];
    final appointments = <Map<String, dynamic>>[];
    final deletedEntities = <Map<String, String>>[];
    final uploadedOpdRecordIds = <String>[];

    for (final entry in pending) {
      final tableName = entry['table_name'] as String? ?? '';
      final operation = entry['operation'] as String? ?? 'upsert';
      final recordId = entry['record_id'] as String? ?? '';

      if (operation == 'delete') {
        deletedEntities.add({'entity_type': tableName, 'entity_id': recordId});
        continue;
      }

      try {
        if (tableName == 'patients') {
          final row = await _patientRepo.getBySyncId(recordId);
          if (row != null) {
            patients.add(await _patientRowToMap(row));
          }
        } else if (tableName == 'opd_visits') {
          final row = await _opdRepo.getByOpdId(recordId);
          if (row != null) {
            opdRecords.add(await _opdRowToMap(row));
            uploadedOpdRecordIds.add(recordId);
          }
        } else if (tableName == 'appointments') {
          try {
            final box = Hive.box<AppointmentModel>('appointments');
            final appt = box.get(recordId);
            if (appt != null) {
              appointments.add(appt.toJson());
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('CLOUD UPLOAD: error building payload for $tableName $recordId: $e');
      }
    }

    if (patients.isEmpty && opdRecords.isEmpty && appointments.isEmpty && deletedEntities.isEmpty) {
      debugPrint('CLOUD UPLOAD: nothing to upload after building payloads');
      return;
    }

    debugPrint('CLOUD DEVICE DEBUG: upload clinic_id=$_clinicId device_id=$_deviceId');
    debugPrint('CLOUD DEVICE DEBUG: upload patients=${patients.length} opd=${opdRecords.length} appts=${appointments.length} deleted=${deletedEntities.length}');
    try {
      final response = await ApiService.cloudUpload(
        deviceId: _deviceId!,
        clinicId: _clinicId!,
        patients: patients,
        opdRecords: opdRecords,
        appointments: appointments,
        deletedEntities: deletedEntities,
      );
      debugPrint('CLOUD_DEBUG: _uploadChanges ApiService.cloudUpload returned response=$response');
      debugPrint('CLOUD DEVICE DEBUG: upload response keys=${response.keys.join(", ")}');
      debugPrint('CLOUD DEVICE DEBUG: stored patients=${(response["results"]?["patients"] as List?)?.length ?? 0}');
      debugPrint('CLOUD DEVICE DEBUG: stored opd_records=${(response["results"]?["opd_records"] as List?)?.length ?? 0}');

      // Mark uploaded entries as synced
      for (final entry in pending) {
        await _cloudQueueRepo.markSynced(entry['id'] as int);
      }

      // Upload images for OPD records that have pending local images.
      // Images can be stored in two places:
      //   1. patient_images SQLite table (file on disk, set by data migration)
      //   2. Hive 'opd_documents' box (base64, set by normal OPD save flow)
      if (uploadedOpdRecordIds.isNotEmpty) {
        debugPrint('CLOUD IMAGE DEBUG: uploadedOpdRecordIds=$uploadedOpdRecordIds');
        try {
          final opdVisitIdsWithPending =
              await _imagesRepo.getDistinctOpdVisitIdsWithPending();
          final docBox = Hive.box('opd_documents');
          for (final uploadedId in uploadedOpdRecordIds) {
            final localRow = await _opdRepo.getByOpdId(uploadedId);
            if (localRow == null) {
              debugPrint('CLOUD IMAGE DEBUG: localRow null for uploadedId=$uploadedId');
              continue;
            }
            final localOpdId = localRow['id'] as int;
            debugPrint(
                'CLOUD IMAGE DEBUG: uploadedId=$uploadedId mapped to localOpdId=$localOpdId');

            File? hiveTempFile;
            List<File> imageFiles = [];

            // Try SQLite patient_images first
            if (opdVisitIdsWithPending.contains(localOpdId)) {
              final pendingImages =
                  await _imagesRepo.getPendingByOpdVisitId(localOpdId);
              debugPrint(
                  'CLOUD IMAGE DEBUG: found local images from SQLite count=${pendingImages.length}');
              for (final img in pendingImages) {
                final path = img['file_path'] as String?;
                debugPrint('CLOUD IMAGE DEBUG: SQLite image path=$path');
                if (path != null && path.isNotEmpty) {
                  final file = File(path);
                  final exists = await file.exists();
                  debugPrint(
                      'CLOUD IMAGE DEBUG: SQLite file exists=$exists for path=$path');
                  if (exists) {
                    imageFiles.add(file);
                  }
                }
              }
            }

            // If nothing in SQLite, try Hive opd_documents box
            if (imageFiles.isEmpty && docBox.containsKey(uploadedId)) {
              final raw = docBox.get(uploadedId);
              debugPrint(
                  'CLOUD IMAGE DEBUG: found Hive opd_documents entry for uploadedId=$uploadedId raw type=${raw.runtimeType}');
              if (raw != null) {
                try {
                  final bytes = base64Decode(raw.toString());
                  hiveTempFile = File(
                    '${Directory.systemTemp.path}/${uploadedId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
                  );
                  await hiveTempFile.writeAsBytes(bytes);
                  imageFiles = [hiveTempFile];
                  debugPrint(
                      'CLOUD IMAGE DEBUG: decoded Hive image to temp file path=${hiveTempFile.path}');
                } catch (e) {
                  debugPrint(
                      'CLOUD IMAGE DEBUG: failed to decode Hive image: $e');
                }
              }
            }

            if (imageFiles.isEmpty) {
              debugPrint(
                  'CLOUD IMAGE: no valid local files for OPD $uploadedId (neither SQLite nor Hive)');
              continue;
            }

            debugPrint(
                'CLOUD IMAGE DEBUG: calling ApiService.cloudUploadImages(opdId=$uploadedId, files=${imageFiles.length})');
            await ApiService.cloudUploadImages(uploadedId, imageFiles);

            // Clean up based on source
            if (opdVisitIdsWithPending.contains(localOpdId)) {
              await _imagesRepo.markSyncedByOpdVisitId(localOpdId);
              debugPrint(
                  'CLOUD IMAGE: SQLite images marked synced for OPD $uploadedId');
            }
            if (docBox.containsKey(uploadedId)) {
              await docBox.delete(uploadedId);
              debugPrint(
                  'CLOUD IMAGE: Hive opd_documents entry deleted for OPD $uploadedId');
            }
            // Delete temp file if we created one
            if (hiveTempFile != null && await hiveTempFile.exists()) {
              await hiveTempFile.delete();
              debugPrint(
                  'CLOUD IMAGE DEBUG: deleted temp file ${hiveTempFile.path}');
            }
            debugPrint('CLOUD IMAGE: completed for OPD $uploadedId');
          }
        } catch (e) {
          debugPrint('CLOUD IMAGE: upload error (non-fatal): $e');
        }
      }

      debugPrint('CLOUD UPLOAD: completed');
    } catch (e) {
      debugPrint('CLOUD_DEBUG: _uploadChanges CAUGHT: $e');
      debugPrint('CLOUD_DEBUG: _uploadChanges stack: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Download remote changes and apply them locally.
  Future<void> _downloadChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString('last_cloud_sync') ?? '';

    debugPrint('CLOUD DEVICE DEBUG: download clinic_id=$_clinicId device_id=$_deviceId last_sync=$lastSync');

    final response = await ApiService.cloudDownload(
      deviceId: _deviceId!,
      clinicId: _clinicId!,
      lastSync: lastSync,
    );

    final remotePatients = response['patients'] as List<dynamic>? ?? [];
    final remoteOpd = response['opd_records'] as List<dynamic>? ?? [];
    final remoteAppts = response['appointments'] as List<dynamic>? ?? [];
    final remoteDeleted = response['deleted_entities'] as List<dynamic>? ?? [];

    debugPrint('CLOUD DEVICE DEBUG: download patients=${remotePatients.length} opd=${remoteOpd.length} appts=${remoteAppts.length} deleted=${remoteDeleted.length}');

    // Apply patients (last-write-wins)
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
            final sqliteId = existing['id'] as int;
            await _patientRepo.update(sqliteId, _remotePatientToRow(map, sqliteId, remoteId));
          } else {
            final maxId = await _patientRepo.getMaxId();
            final newId = maxId + 1;
            await _patientRepo.insert(_remotePatientToRow(map, newId, remoteId));
          }
        }
      } catch (e) {
        debugPrint('CLOUD DOWNLOAD: patient error: $e');
      }
    }

    // Apply OPD records (last-write-wins)
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
              ? existing['id'] as int
              : (await _opdRepo.getMaxId()) + 1;
          final row = await _remoteOpdToRow(map, localId);
          if (existing != null) {
            await _opdRepo.update(localId, row);
          } else {
            await _opdRepo.insert(row);
          }

          // Ensure follow-up appointment in Hive if next_visit_date is set
          final nextVisit = map['next_visit']?.toString() ?? '';
          if (nextVisit.isNotEmpty) {
            final visitDate = DateTime.tryParse(nextVisit);
            if (visitDate != null) {
              try {
                final apptBox = Hive.box<AppointmentModel>('appointments');
                final patientId = map['patient_id']?.toString() ?? '';
                final apptId = 'followup_${remoteId}_$nextVisit';
                if (!apptBox.containsKey(apptId)) {
                  await apptBox.put(apptId, AppointmentModel(
                    id: apptId,
                    patientId: patientId,
                    dateTime: visitDate,
                    notes: 'Follow-up',
                    isSynced: true,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ));
                  debugPrint('CLOUD DOWNLOAD: created Hive follow-up appointment for OPD $remoteId');
                }
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        debugPrint('CLOUD DOWNLOAD: OPD error: $e');
      }
    }

    // Apply appointments (last-write-wins)
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
      } catch (e) {
        debugPrint('CLOUD DOWNLOAD: appointment error: $e');
      }
    }

    // Apply deleted entities
    for (final del in remoteDeleted) {
      try {
        final d = Map<String, dynamic>.from(del as Map);
        final etype = d['entity_type']?.toString() ?? '';
        final eid = d['entity_id']?.toString() ?? '';

        if (etype == 'patients' || etype == 'patient') {
          final local = await _patientRepo.getBySyncId(eid);
          if (local != null) {
            final localId = local['id'] as int;
            final patientOpds = await _opdRepo.getByPatientId(localId);
            for (final opd in patientOpds) {
              final opdSqlId = opd['id'] as int;
              await _imagesRepo.deleteByOpdVisitId(opdSqlId);
            }
            await _opdRepo.deleteByPatientId(localId);
            await _patientRepo.delete(localId);
          }
        } else if (etype == 'opd_visits' || etype == 'opd_visit') {
          final local = await _opdRepo.getByOpdId(eid);
          if (local != null) {
            final localId = local['id'] as int;
            await _imagesRepo.deleteByOpdVisitId(localId);
            // Remove associated follow-up appointment from Hive
            final nextVisit = local['next_visit_date']?.toString() ?? '';
            if (nextVisit.isNotEmpty) {
              try {
                final apptBox = Hive.box<AppointmentModel>('appointments');
                final apptId = 'followup_${eid}_$nextVisit';
                if (apptBox.containsKey(apptId)) {
                  await apptBox.delete(apptId);
                }
              } catch (_) {}
            }
            // Remove associated document image from Hive
            try {
              final docBox = Hive.box('opd_documents');
              if (docBox.containsKey(eid)) {
                await docBox.delete(eid);
              }
            } catch (_) {}
            await _opdRepo.delete(localId);
          }
        } else if (etype == 'appointments' || etype == 'appointment') {
          try {
            final apptBox = Hive.box<AppointmentModel>('appointments');
            if (apptBox.containsKey(eid)) {
              await apptBox.delete(eid);
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('CLOUD DOWNLOAD: delete error: $e');
      }
    }

    // Notify about new data downloaded
    final newCount = remotePatients.length + remoteOpd.length + remoteAppts.length;
    if (newCount > 0) {
      try {
        await EventNotificationService.notifySyncComplete(recordCount: newCount);
        await LocalNotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
          title: 'New Data Synced',
          body: '$newCount new record${newCount == 1 ? '' : 's'} available',
        );
      } catch (_) {}
    }

    // Save last sync timestamp
    final serverTime = response['server_time']?.toString() ?? DateTime.now().toUtc().toIso8601String();
    await prefs.setString('last_cloud_sync', serverTime);
    debugPrint('CLOUD DOWNLOAD: completed, last_sync=$serverTime');
  }

  /// Ensure a valid API token exists for cloud API calls.
  Future<void> _ensureToken() async {
    try {
      await ApiService.ensureToken();
    } catch (e) {
      debugPrint('CLOUD SYNC: token check failed: $e');
    }
  }

  /// Register this device with the cloud server.
  Future<void> _registerDevice() async {
    if (_deviceId == null) return;
    try {
      await ApiService.cloudRegisterDevice(
        deviceId: _deviceId!,
        deviceName: await _getDeviceName(),
        clinicId: _clinicId ?? '',
        appVersion: _getAppVersion(),
      );
      debugPrint('CLOUD DEVICE: registered $_deviceId');
    } catch (e) {
      debugPrint('CLOUD DEVICE: registration failed (will retry): $e');
    }
  }

  /// Send heartbeat to cloud server.
  Future<void> _sendHeartbeat() async {
    if (_deviceId == null) return;
    try {
      await ApiService.cloudHeartbeat(deviceId: _deviceId!);
    } catch (_) {}
  }

  // ─── Helpers ──────────────────────────────────────

  Future<String> _loadOrCreateDeviceId() async {
    final existing = await _deviceRegRepo.get();
    if (existing != null) {
      return existing['device_id'] as String;
    }
    final newId = _generateDeviceId();
    await _deviceRegRepo.insert({
      'device_id': newId,
      'device_name': '',
      'clinic_id': '',
    });
    return newId;
  }

  String _generateDeviceId() {
    final rand = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = rand.nextInt(99999).toString().padLeft(5, '0');
    return 'DEV${ts}_$r';
  }

  Future<String> _getDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('device_name') ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  String _getAppVersion() {
    try {
      return dotenv.env['APP_VERSION'] ?? '1.0.0';
    } catch (_) {
      return '1.0.0';
    }
  }

  // ─── Data Builders (sync with SyncManager's format) ──

  Future<Map<String, dynamic>> _patientRowToMap(Map<String, dynamic> row) async {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    final syncId = row['sync_id'] as String? ?? 'P${row['id']}';
    return {
      'id': syncId,
      'name': row['full_name'],
      'dob': row['dob'] ?? '',
      'age': row['age'] ?? 0,
      'gender': row['gender'] ?? 'Not Specified',
      'blood_group': row['blood_group'] ?? 'Not Specified',
      'mobile': row['mobile_number'],
      'address': row['address'] ?? '',
      'created_at': createdDt.toIso8601String(),
      'updated_at': _resolveUpdatedAt(row),
      'is_synced': 1,
    };
  }

  Future<Map<String, dynamic>> _opdRowToMap(Map<String, dynamic> row) async {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    final visitDt = row['visit_datetime'] as String? ?? '';
    final localPatientId = row['patient_id'] as int? ?? 0;
    String patientSyncId;
    try {
      final patient = await _patientRepo.getById(localPatientId);
      patientSyncId = patient?['sync_id'] as String? ?? 'P$localPatientId';
    } catch (_) {
      patientSyncId = 'P$localPatientId';
    }
    return {
      'id': row['opd_id']?.toString() ?? 'R${row['id']}',
      'patient_id': patientSyncId,
      'type': row['opd_type'] ?? 'consultation',
      'symptoms': row['symptoms'] ?? '',
      'diagnosis': row['diagnosis'] ?? '',
      'medicines': row['medicines'] ?? '',
      'visit_date': DateTime.tryParse(visitDt)?.toIso8601String() ?? createdDt.toIso8601String(),
      'clinical_notes': row['clinical_notes'] ?? '',
      'consultation_fee': (row['consultation_fee'] as num?)?.toString() ?? '',
      'medicine_fee': (row['medicine_fee'] as num?)?.toString() ?? '',
      'discount': (row['discount_value'] as num?)?.toString() ?? '',
      'payment_mode': row['payment_mode'] ?? '',
      'charge_type': row['charge_type'] ?? '',
      'previous_visit_date': '',
      'follow_up_reason': row['followup_status'] ?? '',
      'next_visit': row['next_visit_date'] ?? '',
      'blood_group': '',
      'created_at': createdDt.toIso8601String(),
      'updated_at': _resolveUpdatedAt(row),
      'is_synced': 1,
    };
  }

  Map<String, dynamic> _remotePatientToRow(Map<String, dynamic> remote, int sqliteId, String syncId) {
    return {
      'id': sqliteId,
      'sync_id': syncId,
      'full_name': remote['name']?.toString() ?? '',
      'mobile_number': remote['mobile']?.toString() ?? '',
      'alternate_mobile': null,
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
      localPatientId = patient?['id'] as int? ?? 0;
    } catch (_) {
      localPatientId = 0;
    }
    return {
      'id': sqliteId,
      'opd_id': remote['id']?.toString() ?? '',
      'patient_id': localPatientId,
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
      'followup_status': remote['follow_up_reason']?.toString() ?? '',
      'discount_value': double.tryParse(remote['discount']?.toString() ?? '') ?? 0.0,
      'created_at': remote['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      'updated_at': remote['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
      'medicines': remote['medicines']?.toString() ?? '',
    };
  }

  String _resolveUpdatedAt(Map<String, dynamic> row) {
    final updatedAt = row['updated_at'] as String?;
    if (updatedAt != null && updatedAt.isNotEmpty) return updatedAt;
    final createdAt = row['created_at'] as String?;
    if (createdAt != null && createdAt.isNotEmpty) return createdAt;
    return DateTime.now().toIso8601String();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
