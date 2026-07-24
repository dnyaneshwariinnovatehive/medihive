import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/schema.dart';
import 'sync_metadata_repository.dart';

/// Repository for the immutable `patients` source table.
///
/// `sync_id` and `updated_at` returned from this class are transient metadata
/// fields. They are never written into `clinic.db`.
class PatientRepository {
  final SyncMetadataRepository _metadata = SyncMetadataRepository();

  Future<Database> get _db async => DatabaseHelper().database;

  Future<Map<String, dynamic>> _decorate(Map<String, dynamic> row) async {
    final localId = int.tryParse(row['id']?.toString() ?? '') ?? 0;
    final syncId = await _metadata.patientIdentityForPush(localId);
    final changedAt = await _metadata.changedAt('patient', localId.toString());
    return {
      ...row,
      'sync_id': syncId,
      if (changedAt != null) 'updated_at': changedAt.toUtc().toIso8601String(),
    };
  }

  Future<List<Map<String, dynamic>>> _decorateAll(
    List<Map<String, dynamic>> rows,
  ) async {
    return Future.wait(rows.map(_decorate));
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return _decorateAll(await db.query(tablePatients, orderBy: 'id ASC'));
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      tablePatients,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _decorate(rows.first);
  }

  Future<Map<String, dynamic>?> getBySyncId(String syncId) async {
    if (syncId.isEmpty) return null;
    var localId = await _metadata.localPatientIdForRemote(syncId);
    localId ??= _legacyLocalId(syncId);
    if (localId == null || localId <= 0) return null;
    final patient = await getById(localId);
    if (patient != null &&
        patient['sync_id'] != syncId &&
        syncId.startsWith('P')) {
      await _metadata.bindPatientRemoteId(localId, syncId);
      return {...patient, 'sync_id': syncId};
    }
    return patient;
  }

  int? _legacyLocalId(String syncId) {
    final match = RegExp(r'^P0*(\d+)$').firstMatch(syncId);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Map<String, dynamic> _sourceRow(Map<String, dynamic> row) {
    const sourceColumns = <String>{
      'id',
      'full_name',
      'mobile_number',
      'alternate_mobile',
      'gender',
      'dob',
      'age',
      'blood_group',
      'address',
      'created_at',
    };
    return {
      for (final entry in row.entries)
        if (sourceColumns.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final data = _sourceRow({...row, 'created_at': row['created_at'] ?? now});
    if (data['id'] == null) data.remove('id');
    final localId = await db.insert(tablePatients, data);
    final syncId = row['sync_id']?.toString();
    if (syncId != null && syncId.isNotEmpty) {
      await _metadata.bindPatientRemoteId(localId, syncId);
    }
    await _metadata.markChanged('patient', localId.toString());
    return localId;
  }

  Future<int> update(
    int id,
    Map<String, dynamic> row, {
    bool markSyncChange = true,
  }) async {
    final db = await _db;
    final data = _sourceRow(row)..remove('id');
    final affected = await db.update(
      tablePatients,
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0 && markSyncChange) {
      await _metadata.markChanged('patient', id.toString());
    }
    return affected;
  }

  Future<int> updateSyncId(String oldSyncId, String newSyncId) async {
    final localId =
        await _metadata.localPatientIdForRemote(oldSyncId) ??
        _legacyLocalId(oldSyncId);
    if (localId == null || localId <= 0) return 0;
    await _metadata.bindPatientRemoteId(localId, newSyncId);
    return 1;
  }

  Future<int> delete(int id) async {
    final db = await _db;
    final result = await db.delete(
      tablePatients,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result > 0) await _metadata.removeEntity('patient', id.toString());
    return result;
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tablePatients',
    );
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
      if (seen.add(key)) unique.add(row);
    }
    return _decorateAll(unique);
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final db = await _db;
    return _decorateAll(
      await db.query(
        tablePatients,
        where: 'full_name LIKE ? OR mobile_number LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'full_name ASC',
      ),
    );
  }

  Future<void> clearAll() async {
    final db = await _db;
    await db.delete(tablePatients);
  }

  Future<int> getMaxId() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(id), 0) AS max_id FROM $tablePatients',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
