import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/schema.dart';

class PatientImagesRepository {
  Future<Database> get _db async => DatabaseHelper().database;

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db;
    return db.query(tablePatientImages, orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(tablePatientImages, where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getByPatientId(int patientId) async {
    final db = await _db;
    return db.query(tablePatientImages,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getByOpdVisitId(int opdVisitId) async {
    final db = await _db;
    return db.query(tablePatientImages,
      where: 'opd_visit_id = ?',
      whereArgs: [opdVisitId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingByOpdVisitId(int opdVisitId) async {
    final db = await _db;
    return db.query(
      tablePatientImages,
      where: 'opd_visit_id = ? AND (sync_status = ? OR sync_status IS NULL)',
      whereArgs: [opdVisitId, 'pending'],
    );
  }

  Future<int> markSyncedByOpdVisitId(int opdVisitId) async {
    final db = await _db;
    return db.update(
      tablePatientImages,
      {'sync_status': 'synced'},
      where: 'opd_visit_id = ?',
      whereArgs: [opdVisitId],
    );
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await _db;
    return db.insert(tablePatientImages, {
      'id': row['id'],
      'patient_id': row['patient_id'],
      'opd_visit_id': row['opd_visit_id'],
      'file_path': row['file_path'],
      'image_type': row['image_type'],
      'sync_status': row['sync_status'],
      'uploaded_at': row['uploaded_at'],
      'created_at': row['created_at'],
      'drive_url': row['drive_url'],
    });
  }

  Future<int> update(int id, Map<String, dynamic> row) async {
    final db = await _db;
    return db.update(tablePatientImages, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(tablePatientImages, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteByOpdVisitId(int opdVisitId) async {
    final db = await _db;
    return db.delete(tablePatientImages, where: 'opd_visit_id = ?', whereArgs: [opdVisitId]);
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $tablePatientImages');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
