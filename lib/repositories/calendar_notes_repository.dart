import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class CalendarNotesRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final db = await _db;
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    return columns.any((c) => c['name'] == columnName);
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(
      tableCalendarNotes,
      orderBy: 'note_date DESC',
    );
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      tableCalendarNotes,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getByDate(String noteDate) async {
    final db = await _db;
    final rows = await db.query(
      tableCalendarNotes,
      where: 'note_date = ?',
      whereArgs: [noteDate],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    final hasClinicId = await _hasColumn(tableCalendarNotes, 'clinic_id');
    final data = <String, dynamic>{
      'note_date': row['note_date'],
      'note_text': row['note_text'],
      'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
    };
    if (row.containsKey('id')) {
      data['id'] = row['id'];
    }
    if (hasClinicId) {
      data['clinic_id'] = row['clinic_id'] ?? '';
    }
    return db.insert(tableCalendarNotes, data);
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final hasClinicId = await _hasColumn(tableCalendarNotes, 'clinic_id');
    final data = Map<String, dynamic>.from(row);
    data['updated_at'] = data['updated_at'] ?? DateTime.now().toIso8601String();
    if (!hasClinicId) {
      data.remove('clinic_id');
    } else if (!data.containsKey('clinic_id')) {
      data['clinic_id'] = '';
    }
    return db.update(
      tableCalendarNotes,
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateByDate(String noteDate, Map<String, dynamic> row) async {
    final db = await _db;
    final hasClinicId = await _hasColumn(tableCalendarNotes, 'clinic_id');
    final data = Map<String, dynamic>.from(row);
    data['updated_at'] = data['updated_at'] ?? DateTime.now().toIso8601String();
    if (!hasClinicId) {
      data.remove('clinic_id');
    } else if (!data.containsKey('clinic_id')) {
      data['clinic_id'] = '';
    }
    return db.update(
      tableCalendarNotes,
      data,
      where: 'note_date = ?',
      whereArgs: [noteDate],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(
      tableCalendarNotes,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteByDate(String noteDate) async {
    final db = await _db;
    return db.delete(
      tableCalendarNotes,
      where: 'note_date = ?',
      whereArgs: [noteDate],
    );
  }

  Future<List<Map<String, dynamic>>> getByDateRange(String start, String end) async {
    final db = await _db;
    return db.query(
      tableCalendarNotes,
      where: 'note_date >= ? AND note_date <= ?',
      whereArgs: [start, end],
      orderBy: 'note_date ASC',
    );
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableCalendarNotes',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
