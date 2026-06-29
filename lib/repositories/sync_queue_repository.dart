import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class SyncQueueRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tableSyncQueue, orderBy: 'created_at ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tableSyncQueue, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getByStatus(String status) async {
    final db = await _db;
    return db.query(tableSyncQueue,
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getByEntityType(String entityType) async {
    final db = await _db;
    return db.query(tableSyncQueue,
      where: 'entity_type = ?',
      whereArgs: [entityType],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPending() async {
    final db = await _db;
    final rows = await db.query(tableSyncQueue,
      where: 'status = ? OR status IS NULL',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
    debugPrint('SYNC_QUEUE GETPENDING: count=${rows.length}');
    for (final row in rows) {
      debugPrint('STATUS: ${row['status']} ENTITY_TYPE: ${row['entity_type']} ENTITY_ID: ${row['entity_id']}');
    }
    return rows;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    debugPrint('SYNC_QUEUE INSERT: id=${row['id']} type=${row['entity_type']} entity_id=${row['entity_id']} status=${row['status']}');
    final result = await db.insert(tableSyncQueue, {
      'id': row['id'],
      'entity_type': row['entity_type'],
      'entity_id': row['entity_id'],
      'status': row['status'] ?? 'pending',
      'retry_count': row['retry_count'] ?? 0,
      'last_error': row['last_error'],
      'created_at': row['created_at'],
      'last_attempt': row['last_attempt'],
    });
    debugPrint('SYNC_QUEUE INSERT RESULT: $result');
    return result;
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    return db.update(tableSyncQueue, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tableSyncQueue, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearByEntity(String entityType, String entityId) async {
    final db = await _db;
    return db.delete(tableSyncQueue,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  Future<int> clearProcessed() async {
    final db = await _db;
    return db.delete(tableSyncQueue, where: 'status = ?', whereArgs: ['synced']);
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $tableSyncQueue');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countPending() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM $tableSyncQueue WHERE status = 'pending' OR status IS NULL",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
