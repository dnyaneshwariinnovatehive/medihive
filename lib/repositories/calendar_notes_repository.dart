import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class CalendarNotesRepository {
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
      tableCalendarNotes,
      where: 'clinic_id = ?',
      whereArgs: [clinicId],
      orderBy: 'note_date DESC',
    );
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final rows = await db.query(
      tableCalendarNotes,
      where: 'id = ? AND clinic_id = ?',
      whereArgs: [id, clinicId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getByDate(String noteDate) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final rows = await db.query(
      tableCalendarNotes,
      where: 'note_date = ? AND clinic_id = ?',
      whereArgs: [noteDate, clinicId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final data = <String, dynamic>{
      'clinic_id': row['clinic_id'] ?? clinicId,
      'note_date': row['note_date'],
      'note_text': row['note_text'],
      'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
    };
    if (row.containsKey('id')) {
      data['id'] = row['id'];
    }
    return db.insert(tableCalendarNotes, data);
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final data = Map<String, dynamic>.from(row);
    data['updated_at'] = data['updated_at'] ?? DateTime.now().toIso8601String();
    return db.update(
      tableCalendarNotes,
      data,
      where: 'id = ? AND clinic_id = ?',
      whereArgs: [id, clinicId],
    );
  }

  Future<int> updateByDate(String noteDate, Map<String, dynamic> row) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final data = Map<String, dynamic>.from(row);
    data['updated_at'] = data['updated_at'] ?? DateTime.now().toIso8601String();
    return db.update(
      tableCalendarNotes,
      data,
      where: 'note_date = ? AND clinic_id = ?',
      whereArgs: [noteDate, clinicId],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.delete(
      tableCalendarNotes,
      where: 'id = ? AND clinic_id = ?',
      whereArgs: [id, clinicId],
    );
  }

  Future<int> deleteByDate(String noteDate) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.delete(
      tableCalendarNotes,
      where: 'note_date = ? AND clinic_id = ?',
      whereArgs: [noteDate, clinicId],
    );
  }

  Future<List<Map<String, dynamic>>> getByDateRange(String start, String end) async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    return db.query(
      tableCalendarNotes,
      where: 'note_date >= ? AND note_date <= ? AND clinic_id = ?',
      whereArgs: [start, end, clinicId],
      orderBy: 'note_date ASC',
    );
  }

  Future<int> count() async {
    final db = await _db;
    final clinicId = await _getActiveClinicId();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableCalendarNotes WHERE clinic_id = ?',
      [clinicId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
