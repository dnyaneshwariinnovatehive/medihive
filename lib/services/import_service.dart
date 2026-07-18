import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';
import '../utils/helpers.dart';

class ImportResult {
  final int patientsImported;
  final int patientsSkipped;
  final int opdVisitsImported;
  final int opdVisitsSkipped;
  final bool settingsImported;
  final int notesImported;
  final String error;

  ImportResult({
    this.patientsImported = 0,
    this.patientsSkipped = 0,
    this.opdVisitsImported = 0,
    this.opdVisitsSkipped = 0,
    this.settingsImported = false,
    this.notesImported = 0,
    this.error = '',
  });
}

class ImportService {
  static Future<ImportResult> importFromDesktop(String sourcePath, {bool overwrite = false}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbCopyPath = p.join(appDir.path, 'clinic_import.db');

      await File(sourcePath).copy(dbCopyPath);

      final db = await openDatabase(dbCopyPath);

      int patientsImported = 0, patientsSkipped = 0;
      int opdImported = 0, opdSkipped = 0;
      bool settingsImported = false;
      int notesImported = 0;

      final patientRepo = PatientRepository();
      final opdRepo = OpdRecordRepository();
      final dayNotesBox = Hive.box('day_notes');

      // Map: desktop patient_id => mobile sqlite patient_id
      final patientIdMap = <int, int>{};

      // 1. Import patients
      final allExistingPatients = await patientRepo.getAll();
      final patientRows = await db.rawQuery('SELECT * FROM patients ORDER BY id');
      for (final row in patientRows) {
        final mobile = (row['mobile_number'] as String?)?.trim() ?? '';
        final name = (row['full_name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;

        final existing = allExistingPatients.cast<Map<String, dynamic>?>().firstWhere(
          (p) => (p?['mobile_number'] as String? ?? '') == mobile &&
              (p?['full_name'] as String? ?? '') == name,
          orElse: () => null,
        );

        final desktopId = Helpers.toInt(row['id']);

        if (existing != null && !overwrite) {
          patientIdMap[desktopId] = Helpers.toInt(existing['id']);
          patientsSkipped++;
          continue;
        }

        patientIdMap[desktopId] = desktopId;

        final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_parseDateTime(row['created_at']));
        final patientRow = <String, dynamic>{
          'id': desktopId,
          'full_name': name,
          'dob': (row['dob'] as String?)?.trim() ?? '',
          'age': row['age'] as int? ?? 0,
          'mobile_number': mobile,
          'address': (row['address'] as String?)?.trim() ?? '',
          'gender': _nonEmpty(row['gender'] as String?, 'Not Specified'),
          'blood_group': _nonEmpty(row['blood_group'] as String?, 'Not Specified'),
          'created_at': nowStr,
        };

        if (existing != null) {
          await patientRepo.update(desktopId, patientRow);
        } else {
          await patientRepo.insert(patientRow);
        }
        patientsImported++;
      }

      // 2. Import OPD visits
      final opdRows = await db.rawQuery('SELECT * FROM opd_visits ORDER BY id');
      for (final row in opdRows) {
        final opdId = (row['opd_id'] as String?)?.trim() ?? '';
        final patientId = Helpers.toInt(row['patient_id']);
        if (opdId.isEmpty || patientId == 0) continue;

        final mappedPatientId = patientIdMap[patientId] ?? patientId;

        final existing = await opdRepo.getByOpdId(opdId);
        if (existing != null && !overwrite) {
          opdSkipped++;
          continue;
        }

        final medicines = _buildMedicines(row['medicines'] as String?);
        final visitDtStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_parseDateTime(row['visit_datetime']));
        final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_parseDateTime(row['created_at'] ?? row['visit_datetime']));

        final opdRow = <String, dynamic>{
          'opd_id': opdId,
          'patient_id': mappedPatientId,
          'opd_type': _nonEmpty(row['opd_type'] as String?, 'Consultation'),
          'visit_datetime': visitDtStr,
          'symptoms': (row['symptoms'] as String?)?.trim() ?? '',
          'diagnosis': (row['diagnosis'] as String?)?.trim() ?? '',
          'medicines': medicines,
          'clinical_notes': (row['clinical_notes'] as String?)?.trim() ?? '',
          'consultation_fee': row['consultation_fee'] != null ? (row['consultation_fee'] as num).toDouble() : null,
          'medicine_fee': row['medicine_fee'] != null ? (row['medicine_fee'] as num).toDouble() : null,
          'discount_type': row['discount_type'] as String?,
          'discount_value': row['discount_value'] != null ? (row['discount_value'] as num).toDouble() : null,
          'payment_mode': _nonEmpty(row['payment_mode'] as String?, ''),
          'charge_type': _nonEmpty(row['charge_type'] as String?, ''),
          'next_visit_date': (row['next_visit_date'] as String?)?.trim() ?? '',
          'followup_status': _nonEmpty(row['followup_status'] as String?, ''),
          'created_at': nowStr,
        };

        if (existing != null) {
          await opdRepo.update(Helpers.toInt(existing['id']), opdRow);
        } else {
          await opdRepo.insert(opdRow);
        }
        opdImported++;
      }

      // 3. Import clinic settings
      final settingsRows = await db.rawQuery('SELECT * FROM clinic_settings LIMIT 1');
      if (settingsRows.isNotEmpty) {
        final s = settingsRows.first;
        final prefs = await SharedPreferences.getInstance();

        final existingName = prefs.getString('doctorName') ?? '';
        if (existingName.isEmpty || overwrite) {
          await prefs.setString('doctorName', s['doctor_name'] as String? ?? prefs.getString('doctorName') ?? '');
          await prefs.setString('doctorLicense', s['doctor_license_no'] as String? ?? prefs.getString('doctorLicense') ?? '');
          await prefs.setString('doctorEmail', s['doctor_email'] as String? ?? prefs.getString('doctorEmail') ?? '');
          await prefs.setString('doctorPhone', s['doctor_contact'] as String? ?? prefs.getString('doctorPhone') ?? '');
          await prefs.setString('clinicName', s['clinic_name'] as String? ?? prefs.getString('clinicName') ?? '');
          await prefs.setString('clinicPhone', s['clinic_phone'] as String? ?? prefs.getString('clinicPhone') ?? '');
          await prefs.setString('clinicAddress', s['clinic_address'] as String? ?? prefs.getString('clinicAddress') ?? '');
          await prefs.setString('clinicWebsite', s['website'] as String? ?? prefs.getString('clinicWebsite') ?? '');
        }
        settingsImported = true;
      }

      // 4. Import calendar notes
      final noteRows = await db.rawQuery('SELECT * FROM calendar_notes ORDER BY note_date');
      for (final row in noteRows) {
        final noteDate = (row['note_date'] as String?)?.trim() ?? '';
        final noteText = (row['note_text'] as String?)?.trim() ?? '';
        if (noteDate.isEmpty || noteText.isEmpty) continue;

        final dateParts = noteDate.split('-');
        if (dateParts.length != 3) continue;
        final key = '${int.tryParse(dateParts[0]) ?? 0}-${int.tryParse(dateParts[1]) ?? 0}-${int.tryParse(dateParts[2]) ?? 0}';

        final existing = dayNotesBox.get(key);
        if (existing != null && !overwrite) {
          final list = existing as List;
          if (list.contains(noteText)) continue;
          list.add(noteText);
          await dayNotesBox.put(key, list);
        } else {
          await dayNotesBox.put(key, [noteText]);
        }
        notesImported++;
      }

      await db.close();
      await File(dbCopyPath).delete();

      return ImportResult(
        patientsImported: patientsImported,
        patientsSkipped: patientsSkipped,
        opdVisitsImported: opdImported,
        opdVisitsSkipped: opdSkipped,
        settingsImported: settingsImported,
        notesImported: notesImported,
      );
    } catch (e) {
      return ImportResult(error: e.toString());
    }
  }

  static String _nonEmpty(String? value, String fallback) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? fallback : v;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static String _buildMedicines(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final trimmed = raw.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) return trimmed;
    if (trimmed.contains('\n')) return trimmed;
    final parts = trimmed.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts.map((m) => '{"name": "$m"}').join(',');
  }
}
