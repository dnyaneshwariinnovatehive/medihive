import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';
import '../models/appointment_model.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';

class ExcelRestoreService {
  static final ExcelRestoreService _instance = ExcelRestoreService._internal();
  factory ExcelRestoreService() => _instance;
  ExcelRestoreService._internal();

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    try {
      final parts = dateStr.trim().split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseDateTime(String? dateStr, String? timeStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    final date = _parseDate(dateStr);
    if (date == null) return null;

    if (timeStr == null || timeStr.trim().isEmpty) return date;
    try {
      final amPmParts = timeStr.trim().split(RegExp(r'\s+'));
      final timeParts = amPmParts[0].split(':');
      if (timeParts.length >= 2) {
        var hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        if (amPmParts.length == 2) {
          final amPm = amPmParts[1].toUpperCase();
          if (amPm == 'PM' && hour < 12) hour += 12;
          if (amPm == 'AM' && hour == 12) hour = 0;
        }
        return DateTime(date.year, date.month, date.day, hour, minute);
      }
    } catch (_) {}
    return date;
  }

  int _toSqliteId(String hiveId) {
    return int.tryParse(hiveId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  Future<int> restoreFromExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    final patientRepo = PatientRepository();
    final opdRepo = OpdRecordRepository();
    final apptBox = Hive.box<AppointmentModel>('appointments');

    await patientRepo.clearAll();
    await opdRepo.clearAll();
    await apptBox.clear();

    int totalRestored = 0;
    final Map<String, String> patientNameToId = {};

    final Sheet? patientsSheet = excel.sheets['Patients'];
    if (patientsSheet != null && patientsSheet.maxRows > 1) {
      for (int r = 1; r < patientsSheet.maxRows; r++) {
        final row = patientsSheet.rows[r];
        if (row.isEmpty || row[0]?.value == null) continue;

        final id = row[0]!.value.toString();
        final sqliteId = _toSqliteId(id);
        if (sqliteId == 0) continue;

        final name = row[1]?.value?.toString() ?? '';
        final dob = row[2]?.value?.toString() ?? '';
        final age = int.tryParse(row[3]?.value?.toString() ?? '0') ?? 0;
        final mobile = row[4]?.value?.toString() ?? '';
        final address = row[5]?.value?.toString() ?? '';
        final createdAt = _parseDate(row[8]?.value?.toString()) ?? DateTime.now();

        patientNameToId[name] = id;
        final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(createdAt);

        final patientRow = <String, dynamic>{
          'id': sqliteId,
          'full_name': name,
          'dob': dob,
          'age': age,
          'mobile_number': mobile,
          'address': address,
          'created_at': nowStr,
        };
        await patientRepo.insert(patientRow);
        totalRestored++;
      }
    }

    final Sheet? opdSheet = excel.sheets['OPD Records'];
    if (opdSheet != null && opdSheet.maxRows > 1) {
      for (int r = 1; r < opdSheet.maxRows; r++) {
        final row = opdSheet.rows[r];
        if (row.isEmpty || row[0]?.value == null) continue;

        final opdId = row[0]!.value.toString();
        final patientIdStr = row[1]?.value?.toString() ?? '';
        final patientSqliteId = _toSqliteId(patientIdStr);
        final visitType = row[3]?.value?.toString() ?? 'OPD';
        final visitDate = _parseDate(row[4]?.value?.toString()) ?? DateTime.now();
        final symptoms = row[5]?.value?.toString() ?? '';
        final diagnosis = row[6]?.value?.toString() ?? '';
        final medicines = row[7]?.value?.toString() ?? '';

        final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(visitDate);
        final opdRow = <String, dynamic>{
          'opd_id': opdId,
          'patient_id': patientSqliteId,
          'opd_type': visitType,
          'visit_datetime': nowStr,
          'symptoms': symptoms,
          'diagnosis': diagnosis,
          'medicines': medicines,
          'created_at': nowStr,
        };
        await opdRepo.insert(opdRow);
        totalRestored++;
      }
    }

    final Sheet? apptSheet = excel.sheets['Appointments'];
    if (apptSheet != null && apptSheet.maxRows > 1) {
      for (int r = 1; r < apptSheet.maxRows; r++) {
        final row = apptSheet.rows[r];
        if (row.isEmpty || row[0]?.value == null) continue;

        final id = row[0]!.value.toString();
        final patientName = row[1]?.value?.toString() ?? '';
        final dateStr = row[2]?.value?.toString();
        final timeStr = row[3]?.value?.toString();
        final notes = row[4]?.value?.toString() ?? '';

        final patientId = patientNameToId[patientName] ?? '';
        final dateTime = _parseDateTime(dateStr, timeStr) ?? DateTime.now();

        final appointment = AppointmentModel(
          id: id,
          patientId: patientId,
          dateTime: dateTime,
          notes: notes,
          isSynced: true,
          createdAt: dateTime,
          updatedAt: dateTime,
        );
        await apptBox.put(id, appointment);
        totalRestored++;
      }
    }

    return totalRestored;
  }
}
