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
        break;
      default:
        debugPrint('No migration defined for version $targetVersion');
    }
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
