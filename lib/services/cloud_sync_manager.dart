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
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';

import '../repositories/patient_images_repository.dart';
import '../utils/helpers.dart';
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
  Future<void> notifyChange({
    required String tableName,
    required String operation,
    required String recordId,
    Map<String, dynamic>? payload,
  }) async {
    debugPrint('CLOUD QUEUE: notifyChange called for $operation $tableName $recordId (queue removed)');
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

  /// Upload all local changes directly (no queue tracking).
  Future<void> _uploadChanges() async {
    final patients = <Map<String, dynamic>>[];
    final opdRecords = <Map<String, dynamic>>[];
    final appointments = <Map<String, dynamic>>[];
    final deletedEntities = <Map<String, String>>[];

    try {
      final allPatients = await _patientRepo.getAll();
      for (final row in allPatients) {
        patients.add(await _patientRowToMap(row));
      }
    } catch (e) {
      debugPrint('CLOUD UPLOAD: error building patients: $e');
    }

    try {
      final allOpd = await _opdRepo.getAll();
      for (final row in allOpd) {
        opdRecords.add(await _opdRowToMap(row));
      }
    } catch (e) {
      debugPrint('CLOUD UPLOAD: error building opd records: $e');
    }

    try {
      final box = Hive.box<AppointmentModel>('appointments');
      for (final appt in box.values) {
        appointments.add(appt.toJson());
      }
    } catch (_) {}

    if (patients.isEmpty && opdRecords.isEmpty && appointments.isEmpty && deletedEntities.isEmpty) {
      debugPrint('CLOUD UPLOAD: nothing to upload');
      return;
    }

    debugPrint('CLOUD UPLOAD: patients=${patients.length} opd=${opdRecords.length} appts=${appointments.length}');
    try {
      await ApiService.cloudUpload(
        deviceId: _deviceId!,
        clinicId: _clinicId!,
        patients: patients,
        opdRecords: opdRecords,
        appointments: appointments,
        deletedEntities: deletedEntities,
      );
      debugPrint('CLOUD UPLOAD: completed');
    } catch (e) {
      debugPrint('CLOUD UPLOAD: error: $e');
      rethrow;
    }
  }

  /// Download remote changes and apply them locally.
  Future<void> _downloadChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final String lastSync;

    // On first ever sync (fresh install), use epoch timestamp so ALL
    // existing clinic data is downloaded. Do NOT skip — the cloud is the
    // source of truth and a fresh install must see all records from other
    // devices in the same clinic.
    final rawLastSync = prefs.getString('last_cloud_sync') ?? '';
    if (rawLastSync.isEmpty) {
      lastSync = '2000-01-01T00:00:00';
      debugPrint('CLOUD DOWNLOAD: first sync — using epoch default to download all existing clinic data');
    } else {
      lastSync = rawLastSync;
    }

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
            final sqliteId = Helpers.toInt(existing['id']);
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
            final localId = Helpers.toInt(local['id']);
            final patientOpds = await _opdRepo.getByPatientId(localId);
            for (final opd in patientOpds) {
              final opdSqlId = Helpers.toInt(opd['id']);
              await _imagesRepo.deleteByOpdVisitId(opdSqlId);
            }
            await _opdRepo.deleteByPatientId(localId);
            await _patientRepo.delete(localId);
          }
        } else if (etype == 'opd_visits' || etype == 'opd_visit') {
          final local = await _opdRepo.getByOpdId(eid);
          if (local != null) {
            final localId = Helpers.toInt(local['id']);
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
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('device_id');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = _generateDeviceId();
    await prefs.setString('device_id', newId);
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

  Future<Map<String, dynamic>> _opdRowToMap(Map<String, dynamic> row) async {
    final createdAt = row['created_at'] as String? ?? '';
    final createdDt = DateTime.tryParse(createdAt) ?? DateTime.now();
    final visitDt = row['visit_datetime'] as String? ?? '';
    final localPatientId = Helpers.toInt(row['patient_id']);
    String patientSyncId;
    String patientBloodGroup = '';
    try {
      final patient = await _patientRepo.getById(localPatientId);
      patientSyncId = patient?['sync_id'] as String? ?? 'P$localPatientId';
      patientBloodGroup = patient?['blood_group'] as String? ?? '';
    } catch (_) {
      patientSyncId = 'P$localPatientId';
    }
    final pkNotes = row['panchakarma_notes'] ?? '';
    debugPrint('CLOUD_DEBUG: _opdRowToMap panchakarma_notes="${pkNotes}"');
    return {
      'id': row['opd_id']?.toString() ?? 'R${row['id']}',
      'patient_id': patientSyncId,
      'opd_type': row['opd_type'] ?? 'consultation',
      'symptoms': row['symptoms'] ?? '',
      'diagnosis': row['diagnosis'] ?? '',
      'medicines': row['medicines'] ?? '',
      'visit_datetime': DateTime.tryParse(visitDt)?.toIso8601String() ?? createdDt.toIso8601String(),
      'clinical_notes': row['clinical_notes'] ?? '',
      'panchakarma_notes': pkNotes,
      'consultation_fee': (row['consultation_fee'] as num?)?.toString() ?? '',
      'medicine_fee': (row['medicine_fee'] as num?)?.toString() ?? '',
      'panchakarma_fee': (row['panchakarma_fee'] as num?)?.toString() ?? '',
      'total_fee': (row['total_fee'] as num?)?.toString() ?? '',
      'discount_value': (row['discount_value'] as num?)?.toString() ?? '',
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
      localPatientId = Helpers.toInt(patient?['id']);
    } catch (_) {
      localPatientId = 0;
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
