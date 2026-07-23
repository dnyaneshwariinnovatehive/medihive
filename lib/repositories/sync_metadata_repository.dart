import 'dart:math';

import 'package:hive/hive.dart';

/// Sync-only state deliberately kept outside `clinic.db`.
///
/// `clinic (1).db` is the immutable data contract.  This box holds remote
/// identities and revision timestamps needed for cloud synchronization.
class SyncMetadataRepository {
  static const _boxName = 'sync_metadata';
  static const _patientPrefix = 'patient:';
  static const _patientRemotePrefix = 'patient_remote:';
  static const _entityPrefix = 'entity:';

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }

  Future<void> ensureReady() async {
    await _box();
  }

  String _patientKey(int localId) => '$_patientPrefix$localId';
  String _patientRemoteKey(String remoteId) => '$_patientRemotePrefix$remoteId';
  String _entityKey(String type, String id) => '$_entityPrefix$type:$id';

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _newTemporaryPatientId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final entropy = Random.secure().nextInt(1 << 32).toRadixString(36);
    return 'TEMP_${now}_$entropy';
  }

  /// Binds a local source-table ID to the canonical server patient ID.
  Future<void> bindPatientRemoteId(int localId, String remoteId) async {
    if (localId <= 0 || remoteId.isEmpty) return;
    final box = await _box();
    final old = _asMap(box.get(_patientKey(localId)));
    final oldRemoteId = old['remote_id']?.toString();
    if (oldRemoteId != null &&
        oldRemoteId.isNotEmpty &&
        oldRemoteId != remoteId) {
      await box.delete(_patientRemoteKey(oldRemoteId));
    }
    await box.put(_patientKey(localId), {...old, 'remote_id': remoteId});
    await box.put(_patientRemoteKey(remoteId), localId);
  }

  /// Creates a device-unique temporary ID for a new patient.  The server
  /// replaces it with a canonical P### ID and the mapping is persisted here.
  Future<String> createTemporaryPatientId(int localId) async {
    final current = await patientRemoteId(localId, createIfMissing: false);
    if (current != null && current.isNotEmpty) return current;
    final temporaryId = _newTemporaryPatientId();
    await bindPatientRemoteId(localId, temporaryId);
    return temporaryId;
  }

  Future<String?> patientRemoteId(
    int localId, {
    bool createIfMissing = false,
  }) async {
    if (localId <= 0) return null;
    final box = await _box();
    final value = _asMap(box.get(_patientKey(localId)));
    final remoteId = value['remote_id']?.toString();
    if (remoteId != null && remoteId.isNotEmpty) return remoteId;
    if (!createIfMissing) return null;
    return createTemporaryPatientId(localId);
  }

  /// Legacy source databases used P### identifiers externally.  This fallback
  /// lets existing records sync without modifying their source-table rows.
  Future<String> patientIdentityForPush(int localId) async {
    final mapped = await patientRemoteId(localId);
    return mapped ?? 'P${localId.toString().padLeft(3, '0')}';
  }

  Future<int?> localPatientIdForRemote(String remoteId) async {
    if (remoteId.isEmpty) return null;
    final box = await _box();
    final raw = box.get(_patientRemoteKey(remoteId));
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> migrateLegacyPatients(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      final localId = int.tryParse(row['id']?.toString() ?? '') ?? 0;
      final remoteId = row['sync_id']?.toString() ?? '';
      if (localId > 0 && remoteId.isNotEmpty) {
        await bindPatientRemoteId(localId, remoteId);
      }
      final updatedAt = row['updated_at']?.toString() ?? '';
      if (localId > 0 && updatedAt.isNotEmpty) {
        await markChanged('patient', localId.toString(), updatedAt: updatedAt);
      }
    }
  }

  Future<void> migrateLegacyOpdRecords(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      final opdId = row['opd_id']?.toString() ?? '';
      final updatedAt = row['updated_at']?.toString() ?? '';
      if (opdId.isNotEmpty && updatedAt.isNotEmpty) {
        await markChanged('opd_visit', opdId, updatedAt: updatedAt);
      }
    }
  }

  Future<void> markChanged(
    String entityType,
    String entityId, {
    String? updatedAt,
    int? revision,
  }) async {
    if (entityType.isEmpty || entityId.isEmpty) return;
    final box = await _box();
    final key = _entityKey(entityType, entityId);
    final old = _asMap(box.get(key));
    await box.put(key, {
      ...old,
      'updated_at': updatedAt ?? DateTime.now().toUtc().toIso8601String(),
      if (revision != null) 'revision': revision,
    });
  }

  Future<DateTime?> changedAt(String entityType, String entityId) async {
    final box = await _box();
    final value = _asMap(box.get(_entityKey(entityType, entityId)));
    return DateTime.tryParse(value['updated_at']?.toString() ?? '');
  }

  Future<int> revisionFor(String entityType, String entityId) async {
    final box = await _box();
    final value = _asMap(box.get(_entityKey(entityType, entityId)));
    return int.tryParse(value['revision']?.toString() ?? '') ?? 0;
  }

  Future<void> setRemoteVersion(
    String entityType,
    String entityId, {
    required int revision,
    required String updatedAt,
  }) async {
    await markChanged(
      entityType,
      entityId,
      updatedAt: updatedAt,
      revision: revision,
    );
  }

  Future<void> removeEntity(String entityType, String entityId) async {
    final box = await _box();
    await box.delete(_entityKey(entityType, entityId));
  }
}
