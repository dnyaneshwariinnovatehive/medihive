import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/patient_model.dart';
import '../models/opd_record_model.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class MigrationResult {
  final int patientsHive;
  final int patientsSqlite;
  final int patientsSkipped;
  final int opdVisitsHive;
  final int opdVisitsSqlite;
  final int opdVisitsSkipped;
  final int calendarNotesHive;
  final int calendarNotesSqlite;
  final int calendarNotesSkipped;
  final int patientImagesHive;
  final int patientImagesSqlite;
  final int patientImagesSkipped;
  final int appointmentsSkipped;
  final int draftsSkipped;
  final bool settingsMigrated;
  final int errors;
  final List<String> errorDetails;

  MigrationResult({
    this.patientsHive = 0,
    this.patientsSqlite = 0,
    this.patientsSkipped = 0,
    this.opdVisitsHive = 0,
    this.opdVisitsSqlite = 0,
    this.opdVisitsSkipped = 0,
    this.calendarNotesHive = 0,
    this.calendarNotesSqlite = 0,
    this.calendarNotesSkipped = 0,
    this.patientImagesHive = 0,
    this.patientImagesSqlite = 0,
    this.patientImagesSkipped = 0,
    this.appointmentsSkipped = 0,
    this.draftsSkipped = 0,
    this.settingsMigrated = false,
    this.errors = 0,
    this.errorDetails = const [],
  });

  int get totalHive =>
      patientsHive + opdVisitsHive + calendarNotesHive + patientImagesHive;

  int get totalSqlite =>
      patientsSqlite + opdVisitsSqlite + calendarNotesSqlite + patientImagesSqlite;

  int get totalSkipped =>
      patientsSkipped + opdVisitsSkipped + calendarNotesSkipped +
      patientImagesSkipped + appointmentsSkipped + draftsSkipped;

  @override
  String toString() => '''
═══════════════════════════════════════════
   Hive → SQLite Migration Report
═══════════════════════════════════════════
  Patients       : ${patientsHive.toString().padLeft(4)} Hive → ${patientsSqlite.toString().padLeft(4)} SQLite  ($patientsSkipped skipped)
  OPD Visits     : ${opdVisitsHive.toString().padLeft(4)} Hive → ${opdVisitsSqlite.toString().padLeft(4)} SQLite  ($opdVisitsSkipped skipped)
  Calendar Notes : ${calendarNotesHive.toString().padLeft(4)} Hive → ${calendarNotesSqlite.toString().padLeft(4)} SQLite  ($calendarNotesSkipped skipped)
  Patient Images : ${patientImagesHive.toString().padLeft(4)} Hive → ${patientImagesSqlite.toString().padLeft(4)} SQLite  ($patientImagesSkipped skipped)
  ─────────────────────────────────────────
  Appointments   : $appointmentsSkipped skipped (no SQLite table)
  Drafts         : $draftsSkipped skipped (transient UI state)
  Clinic Settings: ${settingsMigrated ? 'Yes' : 'No'}
  ─────────────────────────────────────────
  Errors         : $errors
  Total Hive     : $totalHive
  Total SQLite   : $totalSqlite
  Total Skipped  : $totalSkipped
═══════════════════════════════════════════''';
}

class DataMigrationService {
  static final DataMigrationService _instance = DataMigrationService._internal();
  factory DataMigrationService() => _instance;
  DataMigrationService._internal();

  final List<String> _errors = [];
  int _errorCount = 0;

  void _logError(String message) {
    _errorCount++;
    _errors.add(message);
    debugPrint('Migration error: $message');
  }

  Future<MigrationResult> migrate() async {
    debugPrint('DataMigrationService: starting Hive → SQLite migration...');

    final db = await DatabaseHelper().database;

    late _PatientMigrationResult result;
    late _OpdMigrationResult opdResult;
    late _SimpleMigrationResult notesResult;
    late _SimpleMigrationResult imagesResult;
    int apptSkipped = 0;
    int draftSkipped = 0;
    bool settingsMigrated = false;

    await db.transaction((txn) async {
      result = await _migratePatients(txn);
      opdResult = await _migrateOpdVisits(txn, result.patientIdMap);
      notesResult = await _migrateCalendarNotes(txn);
      imagesResult = await _migratePatientImages(txn, result.patientIdMap, opdResult.opdIdMap);
      apptSkipped = await _countHiveBox('appointments');
      draftSkipped = await _countHiveBox('drafts');
      settingsMigrated = await _migrateClinicSettings(txn);
    });

    final prefs = await SharedPreferences.getInstance();

    // Clear old Hive boxes that were fully migrated to SQLite
    try {
      if (Hive.isBoxOpen('patients')) {
        await Hive.box<PatientModel>('patients').clear();
      }
      if (Hive.isBoxOpen('opd_records')) {
        await Hive.box<OPDRecordModel>('opd_records').clear();
      }
    } catch (e) {
      // Non-fatal — stale Hive data is harmless
      debugPrint('Migration cleanup warning: $e');
    }

    await prefs.setBool('hive_sqlite_migration_done', true);

    final report = MigrationResult(
      patientsHive: result.hiveCount,
      patientsSqlite: result.sqliteCount,
      patientsSkipped: result.skippedCount,
      opdVisitsHive: opdResult.hiveCount,
      opdVisitsSqlite: opdResult.sqliteCount,
      opdVisitsSkipped: opdResult.skippedCount,
      calendarNotesHive: notesResult.hiveCount,
      calendarNotesSqlite: notesResult.sqliteCount,
      calendarNotesSkipped: notesResult.skippedCount,
      patientImagesHive: imagesResult.hiveCount,
      patientImagesSqlite: imagesResult.sqliteCount,
      patientImagesSkipped: imagesResult.skippedCount,
      appointmentsSkipped: apptSkipped,
      draftsSkipped: draftSkipped,
      settingsMigrated: settingsMigrated,
      errors: _errorCount,
      errorDetails: List.unmodifiable(_errors),
    );

    debugPrint(report.toString());
    return report;
  }

  // ─── Patients ────────────────────────────────────────────────

  Future<_PatientMigrationResult> _migratePatients(DatabaseExecutor db) async {
    final hiveBox = Hive.box<PatientModel>('patients');
    final hiveCount = hiveBox.length;
    int sqliteCount = 0;
    int skippedCount = 0;
    final patientIdMap = <String, int>{};

    if (hiveCount == 0) {
      return _PatientMigrationResult(0, 0, 0, {});
    }

    int nextId = 1;

    for (final patient in hiveBox.values) {
      try {
        final numericId = _extractNumericId(patient.id, nextId);
        if (numericId >= nextId) {
          nextId = numericId + 1;
        }
        patientIdMap[patient.id] = numericId;

        await db.insert(tablePatients, {
          'id': numericId,
          'full_name': patient.name,
          'mobile_number': patient.mobile,
          'alternate_mobile': null,
          'gender': patient.gender,
          'dob': patient.dob.isNotEmpty ? patient.dob : null,
          'age': patient.age > 0 ? patient.age : null,
          'blood_group': patient.bloodGroup,
          'address': patient.address,
          'created_at': patient.createdAt.toIso8601String(),
        });
        sqliteCount++;
      } catch (e) {
        _logError('Patient ${patient.id}: $e');
        skippedCount++;
      }
    }

    return _PatientMigrationResult(hiveCount, sqliteCount, skippedCount, patientIdMap);
  }

  // ─── OPD Visits ──────────────────────────────────────────────

  Future<_OpdMigrationResult> _migrateOpdVisits(
    DatabaseExecutor db,
    Map<String, int> patientIdMap,
  ) async {
    final hiveBox = Hive.box<OPDRecordModel>('opd_records');
    final hiveCount = hiveBox.length;
    int sqliteCount = 0;
    int skippedCount = 0;
    final opdIdMap = <String, int>{};

    if (hiveCount == 0) {
      return _OpdMigrationResult(0, 0, 0, {});
    }

    int nextId = 1;

    for (final record in hiveBox.values) {
      try {
        final numericId = _extractNumericId(record.id, nextId);
        if (numericId >= nextId) {
          nextId = numericId + 1;
        }
        opdIdMap[record.id] = numericId;

        final mappedPatientId = patientIdMap[record.patientId];
        if (mappedPatientId == null) {
          _logError('OPD ${record.id}: patient ${record.patientId} not found, skipping');
          skippedCount++;
          continue;
        }

        final (discountType, discountValue) = _parseDiscount(record.discount);
        final consultationFee = _parseFee(record.consultationFee);
        final medicineFee = _parseFee(record.medicineFee);

        await db.insert(tableOpdVisits, {
          'id': numericId,
          'clinic_id': 1,
          'opd_id': record.id,
          'patient_id': mappedPatientId,
          'visit_datetime': record.visitDate.toIso8601String(),
          'opd_type': record.type,
          'charge_type': record.chargeType.isNotEmpty ? record.chargeType : null,
          'diagnosis': record.diagnosis.isNotEmpty ? record.diagnosis : null,
          'symptoms': record.symptoms.isNotEmpty ? record.symptoms : null,
          'clinical_notes': record.clinicalNotes.isNotEmpty ? record.clinicalNotes : null,
          'consultation_fee': consultationFee,
          'medicine_fee': medicineFee,
          'panchakarma_fee': null,
          'total_fee': null,
          'discount_type': discountType,
          'discount_value': discountValue,
          'payment_mode': record.paymentMode.isNotEmpty ? record.paymentMode : null,
          'next_visit_date': record.nextVisit.isNotEmpty ? record.nextVisit : null,
          'followup_status': record.followUpReason.isNotEmpty ? record.followUpReason : null,
          'created_at': record.createdAt.toIso8601String(),
          'medicines': record.medicines.isNotEmpty ? record.medicines : null,
          'panchakarma_notes': null,
        });
        sqliteCount++;
      } catch (e) {
        _logError('OPD ${record.id}: $e');
        skippedCount++;
      }
    }

    return _OpdMigrationResult(hiveCount, sqliteCount, skippedCount, opdIdMap);
  }

  // ─── Calendar Notes ──────────────────────────────────────────

  Future<_SimpleMigrationResult> _migrateCalendarNotes(DatabaseExecutor db) async {
    final hiveBox = Hive.box('day_notes');
    final hiveCount = hiveBox.length;
    int sqliteCount = 0;
    int skippedCount = 0;

    if (hiveCount == 0) {
      return _SimpleMigrationResult(0, 0, 0);
    }

    int nextId = 1;

    for (final key in hiveBox.keys) {
      try {
        final hiveDateKey = key.toString();
        final normalizedDate = _normalizeDateKey(hiveDateKey);
        if (normalizedDate == null) {
          _logError('Calendar note: invalid date key "$hiveDateKey", skipping');
          skippedCount++;
          continue;
        }

        final rawValue = hiveBox.get(key);
        String noteText;
        if (rawValue is List) {
          noteText = jsonEncode(rawValue.cast<String>());
        } else if (rawValue is String) {
          noteText = rawValue;
        } else {
          noteText = rawValue?.toString() ?? '';
        }

        if (noteText.isEmpty) {
          skippedCount++;
          continue;
        }

        final now = DateTime.now().toIso8601String();

        await db.insert(tableCalendarNotes, {
          'id': nextId++,
          'clinic_id': 1,
          'note_date': normalizedDate,
          'note_text': noteText,
          'created_at': now,
          'updated_at': now,
        });
        sqliteCount++;
      } catch (e) {
        _logError('Calendar note "$key": $e');
        skippedCount++;
      }
    }

    return _SimpleMigrationResult(hiveCount, sqliteCount, skippedCount);
  }

  // ─── Patient Images ──────────────────────────────────────────

  Future<_SimpleMigrationResult> _migratePatientImages(
    DatabaseExecutor db,
    Map<String, int> patientIdMap,
    Map<String, int> opdIdMap,
  ) async {
    final hiveBox = Hive.box('opd_documents');
    final hiveCount = hiveBox.length;
    int sqliteCount = 0;
    int skippedCount = 0;

    if (hiveCount == 0) {
      return _SimpleMigrationResult(0, 0, 0);
    }

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/patient_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    int nextId = 1;

    for (final key in hiveBox.keys) {
      try {
        final opdRecordId = key.toString();
        final mappedOpdId = opdIdMap[opdRecordId];
        if (mappedOpdId == null) {
          _logError('Image: OPD record "$opdRecordId" not found in SQLite, skipping');
          skippedCount++;
          continue;
        }

        final rawValue = hiveBox.get(key);
        if (rawValue == null) {
          skippedCount++;
          continue;
        }

        final bytes = base64Decode(rawValue.toString());
        final fileName = 'img_${mappedOpdId}_$nextId.jpg';
        final filePath = '${imagesDir.path}/$fileName';
        await File(filePath).writeAsBytes(bytes);

        final patientId = await _resolvePatientIdForOpd(db, mappedOpdId, patientIdMap, opdRecordId);

        final now = DateTime.now().toIso8601String();

        await db.insert(tablePatientImages, {
          'id': nextId,
          'patient_id': patientId,
          'opd_visit_id': mappedOpdId,
          'file_path': filePath,
          'image_type': 'document',
          'sync_status': 'pending',
          'uploaded_at': now,
          'created_at': now,
          'drive_url': null,
        });
        nextId++;
        sqliteCount++;
      } catch (e) {
        _logError('Image "$key": $e');
        skippedCount++;
      }
    }

    return _SimpleMigrationResult(hiveCount, sqliteCount, skippedCount);
  }

  Future<int> _resolvePatientIdForOpd(
    DatabaseExecutor db,
    int opdVisitId,
    Map<String, int> patientIdMap,
    String hiveOpdId,
  ) async {
    final rows = await db.query(tableOpdVisits,
      columns: ['patient_id'],
      where: 'id = ?',
      whereArgs: [opdVisitId],
    );
    if (rows.isNotEmpty) {
      return rows.first['patient_id'] as int;
    }
    _logError('Could not resolve patient_id for OPD visit ID $hiveOpdId (SQLite: $opdVisitId)');
    return 0;
  }

  // ─── Clinic Settings ─────────────────────────────────────────

  Future<bool> _migrateClinicSettings(DatabaseExecutor db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doctorName = prefs.getString('doctorName') ?? '';
      if (doctorName.isEmpty) {
        return false;
      }

      final now = DateTime.now().toIso8601String();
      final existing = await db.query(tableClinicSettings, limit: 1);

      if (existing.isNotEmpty) {
        await db.update(tableClinicSettings, {
          'doctor_name': doctorName,
          'doctor_email': prefs.getString('doctorEmail'),
          'doctor_contact': prefs.getString('doctorPhone'),
          'doctor_license_no': prefs.getString('doctorLicense'),
          'clinic_name': prefs.getString('clinicName'),
          'clinic_phone': prefs.getString('clinicPhone'),
          'clinic_address': prefs.getString('clinicAddress'),
          'website': prefs.getString('clinicWebsite'),
          'updated_at': now,
        }, where: 'id = ?', whereArgs: [existing.first['id']]);
      } else {
        await db.insert(tableClinicSettings, {
          'id': 1,
          'doctor_name': doctorName,
          'doctor_email': prefs.getString('doctorEmail'),
          'doctor_contact': prefs.getString('doctorPhone'),
          'doctor_license_no': prefs.getString('doctorLicense'),
          'clinic_name': prefs.getString('clinicName'),
          'clinic_phone': prefs.getString('clinicPhone'),
          'clinic_address': prefs.getString('clinicAddress'),
          'website': prefs.getString('clinicWebsite'),
          'created_at': now,
          'updated_at': now,
        });
      }
      return true;
    } catch (e) {
      _logError('Clinic settings: $e');
      return false;
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────

  int _extractNumericId(String hiveId, int defaultId) {
    final match = RegExp(r'(\d+)').firstMatch(hiveId);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    return defaultId;
  }

  (String?, double?) _parseDiscount(String discount) {
    if (discount.isEmpty) return (null, null);
    final parts = discount.split(': ');
    if (parts.length == 2) {
      final value = double.tryParse(parts[1]);
      if (value != null) return (parts[0], value);
    }
    final value = double.tryParse(discount);
    if (value != null) return (null, value);
    return (null, null);
  }

  double? _parseFee(String fee) {
    if (fee.isEmpty) return null;
    return double.tryParse(fee);
  }

  String? _normalizeDateKey(String hiveKey) {
    final parts = hiveKey.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  Future<int> _countHiveBox(String boxName) async {
    try {
      if (!Hive.isBoxOpen(boxName)) return 0;
      final box = Hive.box(boxName);
      return box.length;
    } catch (e) {
      return 0;
    }
  }
}

// ─── Internal result types ─────────────────────────────────────

class _PatientMigrationResult {
  final int hiveCount;
  final int sqliteCount;
  final int skippedCount;
  final Map<String, int> patientIdMap;
  _PatientMigrationResult(this.hiveCount, this.sqliteCount, this.skippedCount, this.patientIdMap);
}

class _OpdMigrationResult {
  final int hiveCount;
  final int sqliteCount;
  final int skippedCount;
  final Map<String, int> opdIdMap;
  _OpdMigrationResult(this.hiveCount, this.sqliteCount, this.skippedCount, this.opdIdMap);
}

class _SimpleMigrationResult {
  final int hiveCount;
  final int sqliteCount;
  final int skippedCount;
  _SimpleMigrationResult(this.hiveCount, this.sqliteCount, this.skippedCount);
}
