import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';
import '../utils/helpers.dart';

class ClinicSettingsRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tableClinicSettings, orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tableClinicSettings, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getFirst() async {
    final db = await _db;
    final rows = await db.query(tableClinicSettings, limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    return db.insert(tableClinicSettings, row);
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    return db.update(tableClinicSettings, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> upsert(Map<String, dynamic> row) async {
    final existing = await getFirst();
    if (existing != null) {
      return update(Helpers.toInt(existing['id']), row);
    }
    return insert(row);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tableClinicSettings, where: 'id = ?', whereArgs: [id]);
  }
}
