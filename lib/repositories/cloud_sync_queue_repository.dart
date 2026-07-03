import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class CloudSyncQueueRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tableCloudSyncQueue, orderBy: 'created_at ASC');
  }

  Future<List<Map<String, dynamic>>> getPending() async {
    final db = await _db;
    return db.query(
      tableCloudSyncQueue,
      where: 'sync_status = ? OR sync_status IS NULL',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getByStatus(String status) async {
    final db = await _db;
    return db.query(
      tableCloudSyncQueue,
      where: 'sync_status = ?',
      whereArgs: [status],
      orderBy: 'created_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tableCloudSyncQueue, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    return db.insert(tableCloudSyncQueue, {
      'table_name': row['table_name'],
      'operation': row['operation'],
      'record_id': row['record_id'],
      'payload': row['payload'] is String ? row['payload'] : jsonEncode(row['payload']),
      'created_at': row['created_at'] ?? now,
      'updated_at': row['updated_at'] ?? now,
      'sync_status': row['sync_status'] ?? 'pending',
      'retry_count': row['retry_count'] ?? 0,
    });
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    row['updated_at'] = DateTime.now().toIso8601String();
    final db = await _db;
    return db.update(tableCloudSyncQueue, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> markSynced(int id) async {
    return update(id, {
      'sync_status': 'synced',
      'retry_count': 0,
    });
  }

  Future<int> markFailed(int id, {int? retryCount}) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    return db.update(tableCloudSyncQueue, {
      'sync_status': 'failed',
      'retry_count': retryCount ?? 1,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> incrementRetry(int id) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    return db.rawUpdate(
      "UPDATE $tableCloudSyncQueue SET retry_count = retry_count + 1, updated_at = ? WHERE id = ?",
      [now, id],
    );
  }

  Future<void> clearSynced() async {
    final db = await _db;
    await db.delete(tableCloudSyncQueue, where: "sync_status = 'synced'");
  }

  Future<int> countPending() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM $tableCloudSyncQueue WHERE sync_status = 'pending' OR sync_status IS NULL",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery("SELECT COUNT(*) AS cnt FROM $tableCloudSyncQueue");
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
