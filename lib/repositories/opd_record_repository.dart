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
    final db = await _db;
    return db.insert(tableOpdVisits, row);
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    return db.update(tableOpdVisits, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tableOpdVisits, where: 'id = ?', whereArgs: [id]);
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
}
