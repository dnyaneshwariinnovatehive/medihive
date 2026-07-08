import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class OpdRecordRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tableOpdVisits, orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tableOpdVisits, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getByOpdId(String opdId) async {
    final db = await _db;
    final rows = await db.query(tableOpdVisits, where: 'opd_id = ?', whereArgs: [opdId]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    return db.insert(tableOpdVisits, {
      ...row,
      'updated_at': row['updated_at'] ?? row['created_at'] ?? now,
    });
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final affected = await db.update(tableOpdVisits, {
      ...row,
      'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    print('OPD REPO UPDATE: id=$id affectedRows=$affected opd_id=${row['opd_id']} sql=${tableOpdVisits}');
    return affected;
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tableOpdVisits, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteByPatientId(int patientId) async {
    final db = await _db;
    return db.delete(tableOpdVisits, where: 'patient_id = ?', whereArgs: [patientId]);
  }

  Future<List<Map<String, dynamic>>> getByPatientId(int patientId) async {
    final db = await _db;
    return db.query(tableOpdVisits,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'visit_datetime DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getByDateRange(String start, String end) async {
    final db = await _db;
    return db.query(tableOpdVisits,
      where: 'visit_datetime >= ? AND visit_datetime <= ?',
      whereArgs: [start, end],
      orderBy: 'visit_datetime ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getTodayVisits(String todayStart, String todayEnd) async {
    final db = await _db;
    return db.query(tableOpdVisits,
      where: 'visit_datetime >= ? AND visit_datetime < ?',
      whereArgs: [todayStart, todayEnd],
      orderBy: 'visit_datetime ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getByDate(DateTime date) async {
    final db = await _db;
    final start = DateFormat("yyyy-MM-dd'T'00:00:00").format(date);
    final end = DateFormat("yyyy-MM-dd'T'23:59:59").format(date);
    return db.query(tableOpdVisits,
      where: "visit_datetime >= ? AND visit_datetime <= ?",
      whereArgs: [start, end],
      orderBy: 'visit_datetime ASC',
    );
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $tableOpdVisits');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<double> sumConsultationFees(String start, String end) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(consultation_fee), 0) AS total FROM $tableOpdVisits WHERE visit_datetime >= ? AND visit_datetime <= ?',
      [start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await _db;
    return db.query(tableSyncQueue,
      where: 'entity_type = ? AND status = ?',
      whereArgs: ['opd_visit', 'pending'],
    );
  }

  Future<void> clearAll() async {
    final db = await _db;
    await db.delete(tableOpdVisits);
  }

  Future<int> getMaxId() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS max_id FROM $tableOpdVisits');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countTodayFollowUps() async {
    final db = await _db;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableOpdVisits WHERE next_visit_date = ?',
      [today],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countTodayPanchakarmaSessions() async {
    final db = await _db;
    final todayStart = DateFormat("yyyy-MM-dd'T'00:00:00").format(DateTime.now());
    final todayEnd = DateFormat("yyyy-MM-dd'T'23:59:59").format(DateTime.now());
    final result = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM $tableOpdVisits
         WHERE visit_datetime >= ? AND visit_datetime <= ?
         AND (panchakarma_notes IS NOT NULL AND panchakarma_notes != '')''',
      [todayStart, todayEnd],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countPendingPayments() async {
    final db = await _db;
    final result = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM $tableOpdVisits
         WHERE total_fee IS NOT NULL AND total_fee > 0
         AND (payment_mode IS NULL OR payment_mode = '')''',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
