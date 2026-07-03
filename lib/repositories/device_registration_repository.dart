import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class DeviceRegistrationRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<Map<String, dynamic>?> get() async {
    final db = await _db;
    final rows = await db.query(tableDeviceRegistration, limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getByDeviceId(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      tableDeviceRegistration,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    return db.insert(tableDeviceRegistration, {
      'device_id': row['device_id'],
      'device_name': row['device_name'],
      'clinic_id': row['clinic_id'],
      'fcm_token': row['fcm_token'],
      'app_version': row['app_version'],
      'last_seen': row['last_seen'] ?? now,
      'created_at': row['created_at'] ?? now,
      'updated_at': row['updated_at'] ?? now,
    });
  }

  Future<int> update(String deviceId, Map<String, dynamic> row) async {
    row['updated_at'] = DateTime.now().toIso8601String();
    final db = await _db;
    return db.update(
      tableDeviceRegistration, row,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<int> updateLastSeen(String deviceId) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    return db.update(tableDeviceRegistration, {
      'last_seen': now,
      'updated_at': now,
    }, where: 'device_id = ?', whereArgs: [deviceId]);
  }

  Future<int> delete(String deviceId) async {
    final db = await _db;
    return db.delete(tableDeviceRegistration, where: 'device_id = ?', whereArgs: [deviceId]);
  }

  Future<void> clear() async {
    final db = await _db;
    await db.delete(tableDeviceRegistration);
  }
}
