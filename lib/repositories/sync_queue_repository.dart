import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class SyncQueueRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  /// `clinic (1).db` has no operation column.  Preserve the source schema by
  /// encoding operation in the existing, unconstrained entity_type value.
  String _encodeEntityType(String entityType, String operation) {
    final type = entityType.trim().toUpperCase();
    final op = operation.trim().toUpperCase();
    final base = switch (type) {
      'PATIENT' || 'PATIENTS' => 'PATIENT',
      'OPD_VISIT' || 'OPD_VISITS' || 'OPD' => 'OPD',
      _ => type,
    };
    if (base == 'PATIENT' || base == 'OPD') {
      return '${base}_${op == 'DELETE'
          ? 'DELETE'
          : op == 'CREATE'
          ? 'CREATE'
          : 'UPDATE'}';
    }
    return base;
  }

  Map<String, String> _decodeEntityType(String rawType) {
    final raw = rawType.trim().toUpperCase();
    if (raw.startsWith('PATIENT')) {
      return {
        'entity_type': 'patient',
        'operation': raw.endsWith('_DELETE') ? 'delete' : 'upsert',
      };
    }
    if (raw.startsWith('OPD')) {
      return {
        'entity_type': 'opd_visit',
        'operation': raw.endsWith('_DELETE') ? 'delete' : 'upsert',
      };
    }
    return {'entity_type': rawType, 'operation': 'upsert'};
  }

  Map<String, dynamic> _decodedRow(Map<String, dynamic> row) {
    final decoded = _decodeEntityType(row['entity_type']?.toString() ?? '');
    return {
      ...row,
      ...decoded,
      'status': row['status']?.toString().toLowerCase(),
    };
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tableSyncQueue, orderBy: 'created_at ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      tableSyncQueue,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getByStatus(String status) async {
    final db = await _db;
    final rows = await db.query(
      tableSyncQueue,
      where: 'UPPER(status) = ?',
      whereArgs: [status.toUpperCase()],
      orderBy: 'created_at ASC',
    );
    return rows.map(_decodedRow).toList();
  }

  Future<List<Map<String, dynamic>>> getByEntityType(String entityType) async {
    final db = await _db;
    return db.query(
      tableSyncQueue,
      where: 'entity_type = ?',
      whereArgs: [entityType],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPending() async {
    final db = await _db;
    final rows = await db.query(
      tableSyncQueue,
      where: "UPPER(status) = 'PENDING' OR status IS NULL",
      orderBy: 'created_at ASC',
    );
    final decodedRows = rows.map(_decodedRow).toList();
    debugPrint('SYNC_QUEUE GETPENDING: count=${decodedRows.length}');
    for (final row in decodedRows) {
      debugPrint(
        'STATUS: ${row['status']} ENTITY_TYPE: ${row['entity_type']} ENTITY_ID: ${row['entity_id']}',
      );
    }
    return decodedRows;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    debugPrint(
      'SYNC_QUEUE INSERT: id=${row['id']} type=${row['entity_type']} entity_id=${row['entity_id']} status=${row['status']}',
    );
    final entityType = _encodeEntityType(
      row['entity_type']?.toString() ?? '',
      row['operation']?.toString() ?? 'upsert',
    );
    final data = <String, dynamic>{
      'entity_type': entityType,
      'entity_id': row['entity_id'],
      'status': (row['status'] ?? 'PENDING').toString().toUpperCase(),
      'retry_count': row['retry_count'] ?? 0,
      'last_error': row['last_error'],
      'created_at': row['created_at'],
      'last_attempt': row['last_attempt'],
    };
    final result = await db.insert(tableSyncQueue, data);
    debugPrint('SYNC_QUEUE INSERT RESULT: $result');
    return result;
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final data = Map<String, dynamic>.from(row)..remove('operation');
    if (data['status'] != null) {
      data['status'] = data['status'].toString().toUpperCase();
    }
    return db.update(tableSyncQueue, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tableSyncQueue, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearByEntity(String entityType, String entityId) async {
    final db = await _db;
    return db.delete(
      tableSyncQueue,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  Future<int> clearProcessed() async {
    final db = await _db;
    return db.delete(tableSyncQueue, where: "UPPER(status) = 'SYNCED'");
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableSyncQueue',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countPending() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM $tableSyncQueue WHERE UPPER(status) = 'PENDING' OR status IS NULL",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
