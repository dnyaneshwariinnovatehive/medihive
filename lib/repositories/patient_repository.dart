import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class PatientRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tablePatients, orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tablePatients, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    return db.insert(tablePatients, {
      'id': row['id'],
      'full_name': row['full_name'],
      'mobile_number': row['mobile_number'],
      'alternate_mobile': row['alternate_mobile'],
      'gender': row['gender'],
      'dob': row['dob'],
      'age': row['age'],
      'blood_group': row['blood_group'],
      'address': row['address'],
      'created_at': row['created_at'],
    });
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    return db.update(tablePatients, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tablePatients, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $tablePatients');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final db = await _db;
    return db.query(tablePatients,
      where: 'full_name LIKE ? OR mobile_number LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'full_name ASC',
    );
  }

  Future<void> clearAll() async {
    final db = await _db;
    await db.delete(tablePatients);
  }

  Future<int> getMaxId() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS max_id FROM $tablePatients');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
