import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class OpdRecordRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<int> _getActiveClinicId() async {
    final db = await _db;
    try {
      final rows = await db.query(tableClinicSettings, columns: ['id'], limit: 1);
      if (rows.isNotEmpty) {
        return rows.first['id'] as int;
      }
    } catch (_) {}
    return 1; // Default clinic ID fallback
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.query(
      tableOpdVisits,
      where: 'clinic_id = ?',
      whereArgs: [clinicId],
      orderBy: 'id ASC',
    );
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final rows = await db.query(
      tableOpdVisits,
      where: 'id = ? AND clinic_id = ?',
      whereArgs: [id, clinicId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getByOpdId(String opdId) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final rows = await db.query(
      tableOpdVisits,
      where: 'opd_id = ? AND clinic_id = ?',
      whereArgs: [opdId, clinicId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final data = <String, dynamic>{
      ...row,
      'clinic_id': row['clinic_id'] ?? clinicId,
    };
    data.remove('updated_at'); // Remove updated_at since it is no longer in SQLite schema
    return db.insert(tableOpdVisits, data);
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final data = <String, dynamic>{
      ...row,
    };
    data.remove('updated_at'); // Remove updated_at since it is no longer in SQLite schema
    final affected = await db.update(
      tableOpdVisits,
      data,
      where: 'id = ? AND clinic_id = ?',
      whereArgs: [id, clinicId],
    );
    print('OPD REPO UPDATE: id=$id affectedRows=$affected opd_id=${row['opd_id']} sql=${tableOpdVisits}');
    return affected;
  }

  Future<int> delete(int id) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.delete(
      tableOpdVisits,
      where: 'id = ? AND clinic_id = ?',
      whereArgs: [id, clinicId],
    );
  }

  Future<int> deleteByPatientId(int patientId) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.delete(
      tableOpdVisits,
      where: 'patient_id = ? AND clinic_id = ?',
      whereArgs: [patientId, clinicId],
    );
  }

  Future<List<Map<String, dynamic>>> getByPatientId(int patientId) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.query(
      tableOpdVisits,
      where: 'patient_id = ? AND clinic_id = ?',
      whereArgs: [patientId, clinicId],
      orderBy: 'visit_datetime DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getByDateRange(String start, String end) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.query(
      tableOpdVisits,
      where: 'visit_datetime >= ? AND visit_datetime <= ? AND clinic_id = ?',
      whereArgs: [start, end, clinicId],
      orderBy: 'visit_datetime ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getTodayVisits(String todayStart, String todayEnd) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.query(
      tableOpdVisits,
      where: 'visit_datetime >= ? AND visit_datetime < ? AND clinic_id = ?',
      whereArgs: [todayStart, todayEnd, clinicId],
      orderBy: 'visit_datetime ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getByDate(DateTime date) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final start = DateFormat("yyyy-MM-dd'T'00:00:00").format(date);
    final end = DateFormat("yyyy-MM-dd'T'23:59:59").format(date);
    return db.query(
      tableOpdVisits,
      where: "visit_datetime >= ? AND visit_datetime <= ? AND clinic_id = ?",
      whereArgs: [start, end, clinicId],
      orderBy: 'visit_datetime ASC',
    );
  }

  Future<int> count() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableOpdVisits WHERE clinic_id = ?',
      [clinicId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<double> sumConsultationFees(String start, String end) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(consultation_fee), 0) AS total FROM $tableOpdVisits WHERE visit_datetime >= ? AND visit_datetime <= ? AND clinic_id = ?',
      [start, end, clinicId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await _db;
    return db.query(
      tableSyncQueue,
      where: 'entity_type = ? AND status = ?',
      whereArgs: ['opd_visit', 'pending'],
    );
  }

  Future<void> clearAll() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    await db.delete(
      tableOpdVisits,
      where: 'clinic_id = ?',
      whereArgs: [clinicId],
    );
  }

  Future<int> getMaxId() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS max_id FROM $tableOpdVisits');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countTodayFollowUps() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableOpdVisits WHERE next_visit_date = ? AND clinic_id = ?',
      [today, clinicId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countTodayPanchakarmaSessions() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final todayStart = DateFormat("yyyy-MM-dd'T'00:00:00").format(DateTime.now());
    final todayEnd = DateFormat("yyyy-MM-dd'T'23:59:59").format(DateTime.now());
    final result = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM $tableOpdVisits
         WHERE visit_datetime >= ? AND visit_datetime <= ?
         AND clinic_id = ?
         AND (panchakarma_notes IS NOT NULL AND panchakarma_notes != '')''',
      [todayStart, todayEnd, clinicId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countPendingPayments() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final result = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM $tableOpdVisits
         WHERE total_fee IS NOT NULL AND total_fee > 0
         AND clinic_id = ?
         AND (payment_mode IS NULL OR payment_mode = '')''',
      [clinicId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
