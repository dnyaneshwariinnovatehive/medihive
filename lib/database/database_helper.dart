import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'schema.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web.');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, 'medihive.db');
    debugPrint('DATABASE PATH: $dbPath');

    return await openDatabase(
      dbPath,
      version: databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    for (final stmt in createStatements) {
      await db.execute(stmt);
    }

    debugPrint('SQLite database created. Version: $version');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('SQLite migration: $oldVersion → $newVersion');

    for (int v = oldVersion + 1; v <= newVersion; v++) {
      await _applyMigration(db, v);
    }
  }

  Future<void> _applyMigration(Database db, int targetVersion) async {
    switch (targetVersion) {
      case 2:
        await db.execute("ALTER TABLE patients ADD COLUMN updated_at DATETIME");
        await db.execute("ALTER TABLE opd_visits ADD COLUMN updated_at DATETIME");
        debugPrint('Applied migration v2: added updated_at to patients and opd_visits');
        break;
      case 3:
        await db.execute("ALTER TABLE patients ADD COLUMN sync_id TEXT");
        await db.execute("CREATE INDEX ix_patients_sync_id ON patients (sync_id)");
        await db.execute("UPDATE patients SET sync_id = 'P' || SUBSTR('000' || CAST(id AS TEXT), -3, 3) WHERE sync_id IS NULL");
        await db.execute("ALTER TABLE sync_queue ADD COLUMN operation TEXT DEFAULT 'upsert'");
        debugPrint('Applied migration v3: added sync_id to patients and operation to sync_queue');
        break;
      case 4:
        await db.execute(createCloudSyncQueueTable);
        await db.execute(createDeviceRegistrationTable);
        await db.execute(createixCloudSyncQueueStatus);
        await db.execute(createixDeviceRegistrationDeviceId);
        try { await db.execute("ALTER TABLE patients ADD COLUMN clinic_id TEXT"); } catch (_) {}
        try { await db.execute("ALTER TABLE opd_visits ADD COLUMN clinic_id TEXT"); } catch (_) {}
        try { await db.execute("ALTER TABLE sync_queue ADD COLUMN clinic_id TEXT"); } catch (_) {}
        debugPrint('Applied migration v4: added cloud_sync_queue, device_registration, clinic_id columns');
        break;
      case 5:
        await db.execute("ALTER TABLE calendar_notes RENAME TO temp_calendar_notes");
        await db.execute(createCalendarNotesTable);
        try {
          await db.execute('''
            INSERT INTO calendar_notes (note_date, note_text, clinic_id, created_at, updated_at)
            SELECT note_date, note_text, 1, created_at, updated_at FROM temp_calendar_notes
          ''');
        } catch (_) {}
        await db.execute("DROP TABLE temp_calendar_notes");
        debugPrint('Applied migration v5: updated calendar_notes schema and added clinic_id');
        break;
      case 6:
        try { await db.execute("DROP INDEX IF EXISTS ix_opd_visits_opd_id"); } catch (_) {}
        try { await db.execute("DROP INDEX IF EXISTS ix_opd_visits_id"); } catch (_) {}
        await db.execute("ALTER TABLE opd_visits RENAME TO temp_opd_visits");
        await db.execute(createOpdVisitsTable);
        try {
          await db.execute('''
            INSERT INTO opd_visits (
              id, clinic_id, opd_id, patient_id, visit_datetime, opd_type, charge_type,
              diagnosis, symptoms, clinical_notes, consultation_fee, medicine_fee,
              panchakarma_fee, total_fee, discount_type, discount_value, payment_mode,
              next_visit_date, followup_status, created_at, medicines, panchakarma_notes
            )
            SELECT 
              id, COALESCE(NULLIF(CAST(clinic_id AS INTEGER), 0), 1), opd_id, patient_id, visit_datetime, opd_type, charge_type,
              diagnosis, symptoms, clinical_notes, consultation_fee, medicine_fee,
              panchakarma_fee, total_fee, discount_type, discount_value, payment_mode,
              next_visit_date, followup_status, created_at, medicines, panchakarma_notes
            FROM temp_opd_visits
          ''');
        } catch (_) {}
        await db.execute("DROP TABLE temp_opd_visits");
        try { await db.execute(createixOpdVisitsId); } catch (_) {}
        try { await db.execute(createixOpdVisitsOpdId); } catch (_) {}
        debugPrint('Applied migration v6: updated opd_visits schema, added INTEGER clinic_id, removed updated_at');
        break;
      case 7:
        await _applyMigrationV7(db);
        break;
      case 8:
        try {
          await db.execute(createPatientImagesTable);
          await db.execute(createixPatientImagesId);
        } catch (_) {}
        debugPrint('Applied migration v8: created patient_images table');
        break;
      case 9:
        try {
          await db.execute("ALTER TABLE patients RENAME TO temp_patients");
          await db.execute(createPatientsTable);
          try {
            await db.execute('''
              INSERT INTO patients (
                id, clinic_id, full_name, mobile_number, alternate_mobile,
                gender, dob, age, blood_group, address, created_at, updated_at, sync_id
              )
              SELECT
                id, clinic_id, full_name, mobile_number, alternate_mobile,
                gender, dob, age, blood_group, address, created_at, updated_at, sync_id
              FROM temp_patients
            ''');
          } catch (e) {
            debugPrint('Migration v9 patients copy failed: \$e');
          }
          await db.execute("DROP TABLE temp_patients");
          try { await db.execute(createixPatientsId); } catch (_) {}
          try { await db.execute(createixPatientsSyncId); } catch (_) {}
        } catch (_) {}
        debugPrint('Applied migration v9: recreated patients table with updated constraints');
        break;
      case 10:
        try {
          // 1. calendar_notes
          try { await db.execute("ALTER TABLE calendar_notes RENAME TO temp_calendar_notes"); } catch (_) {}
          await db.execute(createCalendarNotesTable);
          try {
            await db.execute('''
              INSERT INTO calendar_notes (id, clinic_id, note_date, note_text, created_at, updated_at)
              SELECT id, 'CLI001', note_date, note_text, created_at, updated_at FROM temp_calendar_notes
            ''');
          } catch (e) {
            debugPrint('Migration v10 calendar_notes copy failed: \$e');
          }
          try { await db.execute("DROP TABLE temp_calendar_notes"); } catch (_) {}

          // 2. clinic_settings
          try { await db.execute("ALTER TABLE clinic_settings RENAME TO temp_clinic_settings"); } catch (_) {}
          await db.execute(createClinicSettingsTable);
          try {
            await db.execute('''
              INSERT INTO clinic_settings (
                id, clinic_id, doctor_name, doctor_email, doctor_contact, doctor_license_no, doctor_photo_path,
                clinic_name, clinic_logo_path, clinic_address, clinic_phone, website, operating_hours,
                smtp_email, smtp_password, smtp_server, smtp_port, created_at, updated_at
              )
              SELECT
                id, 'CLI001', doctor_name, doctor_email, doctor_contact, doctor_license_no, doctor_photo_path,
                clinic_name, clinic_logo_path, clinic_address, clinic_phone, website, operating_hours,
                smtp_email, smtp_password, smtp_server, smtp_port, created_at, updated_at
              FROM temp_clinic_settings
            ''');
          } catch (e) {
            debugPrint('Migration v10 clinic_settings copy failed: \$e');
          }
          try { await db.execute("DROP TABLE temp_clinic_settings"); } catch (_) {}
          try { await db.execute(createixClinicSettingsId); } catch (_) {}

          // 3. medicines
          try { await db.execute("ALTER TABLE medicines RENAME TO temp_medicines"); } catch (_) {}
          await db.execute(createMedicinesTable);
          try {
            await db.execute('''
              INSERT INTO medicines (id, clinic_id, name)
              SELECT id, 'CLI001', name FROM temp_medicines
            ''');
          } catch (e) {
            debugPrint('Migration v10 medicines copy failed: \$e');
          }
          try { await db.execute("DROP TABLE temp_medicines"); } catch (_) {}

          // 4. symptoms_master
          try { await db.execute("ALTER TABLE symptoms_master RENAME TO temp_symptoms_master"); } catch (_) {}
          await db.execute(createSymptomsMasterTable);
          try {
            await db.execute('''
              INSERT INTO symptoms_master (id, clinic_id, name)
              SELECT id, 'CLI001', name FROM temp_symptoms_master
            ''');
          } catch (e) {
            debugPrint('Migration v10 symptoms_master copy failed: \$e');
          }
          try { await db.execute("DROP TABLE temp_symptoms_master"); } catch (_) {}

          // 5. sync_queue
          try { await db.execute("ALTER TABLE sync_queue RENAME TO temp_sync_queue"); } catch (_) {}
          await db.execute(createSyncQueueTable);
          try {
            await db.execute('''
              INSERT INTO sync_queue (
                id, clinic_id, entity_type, entity_id, operation, status, retry_count, last_error, created_at, last_attempt
              )
              SELECT
                id, COALESCE(clinic_id, 'CLI001'), entity_type, entity_id, operation, status, COALESCE(retry_count, 0), last_error, created_at, last_attempt
              FROM temp_sync_queue
            ''');
          } catch (e) {
            debugPrint('Migration v10 sync_queue copy failed: \$e');
          }
          try { await db.execute("DROP TABLE temp_sync_queue"); } catch (_) {}
          try { await db.execute(createixSyncQueueId); } catch (_) {}

          // 6. users
          try { await db.execute("ALTER TABLE users RENAME TO temp_users"); } catch (_) {}
          await db.execute(createUsersTable);
          try {
            await db.execute('''
              INSERT INTO users (id, clinic_id, username, password_hash, email, role, created_at, reset_otp, otp_expiry)
              SELECT id, 'CLI001', username, password_hash, email, 'Doctor', created_at, reset_otp, otp_expiry FROM temp_users
            ''');
          } catch (e) {
            debugPrint('Migration v10 users copy failed: \$e');
          }
          try { await db.execute("DROP TABLE temp_users"); } catch (_) {}
          try { await db.execute(createixUsersId); } catch (_) {}
        } catch (_) {}
        debugPrint('Applied migration v10: updated schemas for calendar_notes, clinic_settings, medicines, symptoms_master, sync_queue, users');
        break;
      case 11:
        try {
          await db.execute("ALTER TABLE patients ADD COLUMN updated_at DATETIME");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE opd_visits ADD COLUMN updated_at DATETIME");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE patients ADD COLUMN sync_id TEXT");
        } catch (_) {}
        debugPrint('Applied migration v11: added updated_at/sync_id columns to match manager schema');
        break;
      case 12:
        // Ensure all core tables exist (from manager schema)
        try { await db.execute(createPatientsTable); } catch (_) {}
        try { await db.execute(createOpdVisitsTable); } catch (_) {}
        try { await db.execute(createCalendarNotesTable); } catch (_) {}
        try { await db.execute(createClinicSettingsTable); } catch (_) {}
        try { await db.execute(createUsersTable); } catch (_) {}
        try { await db.execute(createMedicinesTable); } catch (_) {}
        try { await db.execute(createSymptomsMasterTable); } catch (_) {}
        try { await db.execute(createPatientImagesTable); } catch (_) {}
        try { await db.execute(createSyncQueueTable); } catch (_) {}
        try { await db.execute(createCloudSyncQueueTable); } catch (_) {}
        try { await db.execute(createDeviceRegistrationTable); } catch (_) {}
        try { await db.execute(createixPatientsId); } catch (_) {}
        try { await db.execute(createixPatientsSyncId); } catch (_) {}
        try { await db.execute(createixOpdVisitsId); } catch (_) {}
        try { await db.execute(createixOpdVisitsOpdId); } catch (_) {}
        try { await db.execute(createixPatientImagesId); } catch (_) {}
        try { await db.execute(createixSyncQueueId); } catch (_) {}
        try { await db.execute(createixUsersId); } catch (_) {}
        try { await db.execute(createixClinicSettingsId); } catch (_) {}
        try { await db.execute(createixCloudSyncQueueStatus); } catch (_) {}
        try { await db.execute(createixDeviceRegistrationDeviceId); } catch (_) {}
        debugPrint('Applied migration v12: ensured all core tables and indexes exist');
        break;
      default:
        debugPrint('No migration defined for version $targetVersion');
    }
  }

  Future<void> _applyMigrationV7(Database db) async {
    // Recreate opd_visits: change DECIMAL(10,2) → FLOAT, TEXT → VARCHAR for clinical_notes,
    // make clinic_id nullable, match provided database schema exactly
    try { await db.execute("DROP INDEX IF EXISTS ix_opd_visits_opd_id"); } catch (_) {}
    try { await db.execute("DROP INDEX IF EXISTS ix_opd_visits_id"); } catch (_) {}

    await db.execute("ALTER TABLE opd_visits RENAME TO temp_opd_visits");
    await db.execute(createOpdVisitsTable);
    try {
      await db.execute('''
        INSERT INTO opd_visits (
          id, opd_id, patient_id, clinic_id, visit_datetime, opd_type, charge_type,
          diagnosis, symptoms, clinical_notes, consultation_fee, medicine_fee,
          panchakarma_fee, total_fee, discount_type, discount_value, payment_mode,
          next_visit_date, followup_status, created_at, medicines, panchakarma_notes
        )
        SELECT
          id, opd_id, patient_id, clinic_id, visit_datetime, opd_type, charge_type,
          diagnosis, symptoms, clinical_notes, consultation_fee, medicine_fee,
          panchakarma_fee, total_fee, discount_type, discount_value, payment_mode,
          next_visit_date, followup_status, created_at, medicines, panchakarma_notes
        FROM temp_opd_visits
      ''');
    } catch (e) {
      debugPrint('Migration v7 opd_visits copy failed: $e');
    }
    await db.execute("DROP TABLE temp_opd_visits");
    try { await db.execute(createixOpdVisitsId); } catch (_) {}
    try { await db.execute(createixOpdVisitsOpdId); } catch (_) {}

    // Recreate calendar_notes: remove FK constraint, make clinic_id nullable,
    // change UNIQUE(clinic_id, note_date) → UNIQUE(note_date)
    try {
      await db.execute("ALTER TABLE calendar_notes RENAME TO temp_calendar_notes");
      await db.execute(createCalendarNotesTable);
      try {
        await db.execute('''
          INSERT INTO calendar_notes (id, clinic_id, note_date, note_text, created_at, updated_at)
          SELECT id, clinic_id, note_date, note_text, created_at, updated_at
          FROM temp_calendar_notes
        ''');
      } catch (e) {
        debugPrint('Migration v7 calendar_notes copy failed: $e');
      }
      await db.execute("DROP TABLE temp_calendar_notes");
    } catch (_) {}

    // Add clinic_id to patient_images if not present
    try {
      await db.execute("ALTER TABLE patient_images ADD COLUMN clinic_id INTEGER");
    } catch (_) {}

    debugPrint('Applied migration v7: matched provided database schema, FLOAT fees, nullable clinic_id, removed FK constraints');
  }

  Future<bool> isInitialized() async {
    try {
      await database;
      return true;
    } catch (e) {
      debugPrint('DatabaseHelper.isInitialized error: $e');
      return false;
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
