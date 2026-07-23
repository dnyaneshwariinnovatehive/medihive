import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../repositories/sync_metadata_repository.dart';
import 'schema.dart';

/// Opens the clinic database using the exact schema in `clinic (1).db`.
///
/// Synchronization state deliberately lives outside this database.  It is
/// stored in Hive by [SyncMetadataRepository], which lets a clinic database be
/// exchanged with the reference application without schema changes.
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

    return openDatabase(
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
    for (final statement in createStatements) {
      await db.execute(statement);
    }
    debugPrint('Created source-contract SQLite database. Version: $version');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // A single reconstruction is safer than applying historical migrations
    // that created columns which are absent from the source-of-truth database.
    await _migrateToSourceContract(db, oldVersion, newVersion);
  }

  Future<bool> _tableExists(Database db, String table) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return result.isNotEmpty;
  }

  Future<Set<String>> _columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name']?.toString() ?? '').toSet();
  }

  Future<List<Map<String, dynamic>>> _legacyRows(
    Database db,
    String table,
    List<String> columns,
  ) async {
    if (!await _tableExists(db, table)) return const [];
    final present = await _columns(db, table);
    final selected = columns.where(present.contains).toList();
    if (selected.isEmpty) return const [];
    return db.query(table, columns: selected);
  }

  Future<void> _preserveLegacySyncMetadata(Database db) async {
    try {
      final metadata = SyncMetadataRepository();
      await metadata.ensureReady();
      await metadata.migrateLegacyPatients(
        await _legacyRows(db, tablePatients, const [
          'id',
          'sync_id',
          'updated_at',
        ]),
      );
      await metadata.migrateLegacyOpdRecords(
        await _legacyRows(db, tableOpdVisits, const ['opd_id', 'updated_at']),
      );
    } catch (error) {
      // The source rows remain intact even if Hive cannot be opened.  The
      // caller can safely retry after app startup completes.
      debugPrint('Could not preserve legacy sync metadata: $error');
    }
  }

  Future<void> _copyCommonColumns(
    Database db, {
    required String from,
    required String to,
    required List<String> sourceColumns,
    String? where,
  }) async {
    final legacyColumns = await _columns(db, from);
    final columns = sourceColumns.where(legacyColumns.contains).toList();
    if (columns.isEmpty) return;
    final names = columns.join(', ');
    await db.execute(
      'INSERT INTO $to ($names) SELECT $names FROM $from${where == null ? '' : ' WHERE $where'}',
    );
  }

  String _canonicalQueueEntityType(Map<String, dynamic> row) {
    final rawType = row['entity_type']?.toString().trim() ?? '';
    final operation = row['operation']?.toString().trim().toLowerCase() ?? '';
    final normalized = rawType.toUpperCase();
    if (normalized == 'PATIENT' || normalized == 'PATIENTS') {
      return operation == 'delete' ? 'PATIENT_DELETE' : 'PATIENT_UPDATE';
    }
    if (normalized == 'OPD_VISIT' ||
        normalized == 'OPD_VISITS' ||
        normalized == 'OPD') {
      return operation == 'delete' ? 'OPD_DELETE' : 'OPD_UPDATE';
    }
    return normalized.isEmpty ? 'OPD_UPDATE' : normalized;
  }

  Future<void> _copyQueue(Database db, String legacyTable) async {
    final rows = await db.query(legacyTable);
    for (final row in rows) {
      await db.insert(tableSyncQueue, {
        if (row['id'] != null) 'id': row['id'],
        'entity_type': _canonicalQueueEntityType(row),
        'entity_id': row['entity_id']?.toString() ?? '',
        'status': row['status']?.toString().toUpperCase(),
        'retry_count': row['retry_count'],
        'last_error': row['last_error'],
        'created_at': row['created_at'],
        'last_attempt': row['last_attempt'],
      });
    }
  }

  Future<void> _migrateToSourceContract(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint(
      'SQLite migration: $oldVersion -> $newVersion (source contract)',
    );
    await _preserveLegacySyncMetadata(db);

    final tables = <String>[
      tablePatients,
      tableOpdVisits,
      tableCalendarNotes,
      tableClinicSettings,
      tableUsers,
      tableMedicines,
      tableSymptomsMaster,
      tablePatientImages,
      tableSyncQueue,
    ];
    final legacyNames = <String, String>{};

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      for (final table in tables) {
        if (await _tableExists(db, table)) {
          final indexRows = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND name NOT LIKE 'sqlite\\_autoindex\\_%' ESCAPE '\\'",
            [table],
          );
          for (final row in indexRows) {
            await db.execute('DROP INDEX IF EXISTS "${row['name']}"');
          }

          final legacy = '${table}_pre_source_v13';
          if (await _tableExists(db, legacy)) {
            await db.execute('DROP TABLE $legacy');
          }
          await db.execute('ALTER TABLE $table RENAME TO $legacy');
          legacyNames[table] = legacy;
        }
      }

      for (final statement in createStatements) {
        await db.execute(statement);
      }

      final patients = legacyNames[tablePatients];
      if (patients != null) {
        await _copyCommonColumns(
          db,
          from: patients,
          to: tablePatients,
          sourceColumns: const [
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
            'weight',
          ],
        );
      }

      final opdVisits = legacyNames[tableOpdVisits];
      if (opdVisits != null) {
        await _copyCommonColumns(
          db,
          from: opdVisits,
          to: tableOpdVisits,
          sourceColumns: const [
            'id',
            'opd_id',
            'patient_id',
            'visit_datetime',
            'opd_type',
            'charge_type',
            'diagnosis',
            'symptoms',
            'clinical_notes',
            'consultation_fee',
            'medicine_fee',
            'panchakarma_fee',
            'total_fee',
            'discount_type',
            'discount_value',
            'payment_mode',
            'next_visit_date',
            'followup_status',
            'created_at',
            'medicines',
            'panchakarma_notes',
          ],
        );
      }

      for (final table in [
        tableCalendarNotes,
        tableClinicSettings,
        tableUsers,
        tableMedicines,
        tableSymptomsMaster,
      ]) {
        final legacy = legacyNames[table];
        if (legacy == null) continue;
        final sourceColumns = switch (table) {
          tableCalendarNotes => const [
            'id',
            'note_date',
            'note_text',
            'created_at',
            'updated_at',
          ],
          tableClinicSettings => const [
            'id',
            'doctor_name',
            'doctor_email',
            'doctor_contact',
            'doctor_license_no',
            'doctor_photo_path',
            'clinic_name',
            'clinic_logo_path',
            'clinic_address',
            'clinic_phone',
            'website',
            'operating_hours',
            'smtp_email',
            'smtp_password',
            'smtp_server',
            'smtp_port',
            'created_at',
            'updated_at',
          ],
          tableUsers => const [
            'id',
            'username',
            'password_hash',
            'email',
            'created_at',
            'reset_otp',
            'otp_expiry',
          ],
          tableMedicines || tableSymptomsMaster => const ['id', 'name'],
          _ => const <String>[],
        };
        await _copyCommonColumns(
          db,
          from: legacy,
          to: table,
          sourceColumns: sourceColumns,
        );
      }

      final images = legacyNames[tablePatientImages];
      if (images != null) {
        // The reference database requires an OPD relation.  Rows without one
        // were never valid source rows and cannot be represented faithfully.
        await _copyCommonColumns(
          db,
          from: images,
          to: tablePatientImages,
          sourceColumns: const [
            'id',
            'patient_id',
            'opd_visit_id',
            'file_path',
            'image_type',
            'sync_status',
            'uploaded_at',
            'created_at',
            'drive_url',
          ],
          where: 'opd_visit_id IS NOT NULL',
        );
      }

      final queue = legacyNames[tableSyncQueue];
      if (queue != null) {
        await _copyQueue(db, queue);
      }

      for (final legacy in legacyNames.values) {
        await db.execute('DROP TABLE $legacy');
      }
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<bool> isInitialized() async {
    try {
      await database;
      return true;
    } catch (error) {
      debugPrint('DatabaseHelper.isInitialized error: $error');
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
