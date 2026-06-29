import 'package:intl/intl.dart';
import 'package:hive/hive.dart';
import '../models/appointment_model.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';

class LocalStorageService {
  // ─── Patient Methods ──────────────────────────────────────────

  Future<void> savePatient(Map<String, dynamic> patient) async {
    final repo = PatientRepository();
    final id = patient['id'] as int? ?? 0;
    if (id == 0) return;
    final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    patient['created_at'] ??= nowStr;
    final existing = await repo.getById(id);
    if (existing != null) {
      await repo.update(id, patient);
    } else {
      await repo.insert(patient);
    }
  }

  Future<List<Map<String, dynamic>>> getPatients() async {
    return PatientRepository().getAll();
  }

  Future<void> updatePatient(Map<String, dynamic> patient) async {
    await savePatient(patient);
  }

  Future<void> deletePatient(String id) async {
    final sqliteId = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (sqliteId != 0) {
      await PatientRepository().delete(sqliteId);
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSyncPatients() async {
    return [];
  }

  // ─── OPD Record Methods ───────────────────────────────────────

  Future<void> saveOPDRecord(Map<String, dynamic> record) async {
    final repo = OpdRecordRepository();
    final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    record['created_at'] ??= nowStr;
    await repo.insert(record);
  }

  Future<List<Map<String, dynamic>>> getOPDRecords() async {
    return OpdRecordRepository().getAll();
  }

  Future<List<Map<String, dynamic>>> getPendingSyncRecords() async {
    return [];
  }

  Future<void> deleteOPDRecord(String id) async {
    final sqliteId = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (sqliteId != 0) {
      await OpdRecordRepository().delete(sqliteId);
    }
  }

  // ─── Appointment Methods ──────────────────────────────────────

  Future<void> saveAppointment(AppointmentModel appointment) async {
    final box = Hive.box<AppointmentModel>('appointments');
    final exists = box.containsKey(appointment.id);
    final now = DateTime.now();

    final appointmentToSave = appointment.copyWith(
      isSynced: false,
      createdAt: exists ? (box.get(appointment.id)?.createdAt ?? appointment.createdAt) : now,
      updatedAt: now,
    );
    await box.put(appointmentToSave.id, appointmentToSave);
  }

  List<AppointmentModel> getAppointments() {
    final box = Hive.box<AppointmentModel>('appointments');
    return box.values.toList();
  }

  Future<void> updateAppointment(AppointmentModel appointment) async {
    await saveAppointment(appointment);
  }

  Future<void> deleteAppointment(String id) async {
    final box = Hive.box<AppointmentModel>('appointments');
    await box.delete(id);
  }

  List<AppointmentModel> getPendingSyncAppointments() {
    final box = Hive.box<AppointmentModel>('appointments');
    return box.values.where((a) => !a.isSynced).toList();
  }

  // ─── Draft Methods ────────────────────────────────────────────

  Future<void> saveDraft(String key, Map<String, dynamic> draftData) async {
    final box = Hive.box('drafts');
    await box.put(key, draftData);
  }

  Map<String, dynamic>? getDraft(String key) {
    final box = Hive.box('drafts');
    final data = box.get(key);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<void> clearDraft(String key) async {
    final box = Hive.box('drafts');
    await box.delete(key);
  }
}
