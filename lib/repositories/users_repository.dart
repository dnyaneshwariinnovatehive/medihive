import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class UsersRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tableUsers, orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tableUsers, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getByUsername(String username) async {
    final db = await _db;
    final rows = await db.query(tableUsers, where: 'username = ?', whereArgs: [username]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    return db.insert(tableUsers, {
      'id': row['id'],
      'username': row['username'],
      'password_hash': row['password_hash'],
      'email': row['email'],
      'created_at': row['created_at'],
      'reset_otp': row['reset_otp'],
      'otp_expiry': row['otp_expiry'],
    });
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    return db.update(tableUsers, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tableUsers, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $tableUsers');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
