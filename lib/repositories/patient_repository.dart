import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class PatientRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final db = await _db;
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    return columns.any((c) => c['name'] == columnName);
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tablePatients, orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tablePatients, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getBySyncId(String syncId) async {
    final db = await _db;
    final rows = await db.query(
      tablePatients,
      where: 'sync_id = ?',
      whereArgs: [syncId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    final hasUpdatedAt = await _hasColumn(tablePatients, 'updated_at');
    final data = <String, dynamic>{
      'id': row['id'],
      'sync_id': row['sync_id'],
      'full_name': row['full_name'],
      'mobile_number': row['mobile_number'],
      'alternate_mobile': row['alternate_mobile'],
      'gender': row['gender'],
      'dob': row['dob'],
      'age': row['age'],
      'blood_group': row['blood_group'],
      'address': row['address'],
      'created_at': row['created_at'] ?? now,
    };
    if (hasUpdatedAt) {
      data['updated_at'] = row['updated_at'] ?? row['created_at'] ?? now;
    }
    return db.insert(tablePatients, data);
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final hasUpdatedAt = await _hasColumn(tablePatients, 'updated_at');
    final data = Map<String, dynamic>.from(row);
    if (hasUpdatedAt) {
      data['updated_at'] = data['updated_at'] ?? DateTime.now().toIso8601String();
    } else {
      data.remove('updated_at');
    }
    data.remove('clinic_id');
    final affected = await db.update(tablePatients, data, where: 'id = ?', whereArgs: [id]);
    print('PATIENT REPO UPDATE: id=$id affectedRows=$affected');
    return affected;
  }

  Future<int> updateSyncId(String oldSyncId, String newSyncId) async {
    final db = await _db;
    return db.update(
      tablePatients,
      {'sync_id': newSyncId},
      where: 'sync_id = ?',
      whereArgs: [oldSyncId],
    );
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

  Future<List<Map<String, dynamic>>> getByMobile(String mobile) async {
    final db = await _db;
    final rows = await db.query(
      tablePatients,
      where: 'mobile_number = ?',
      whereArgs: [mobile],
      orderBy: 'full_name ASC',
    );
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final row in rows) {
      final key = '${row['full_name']}|${row['gender']}|${row['dob']}';
      if (seen.add(key)) {
        unique.add(row);
      }
    }
    return unique;
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
