import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDb {
  static final LocalDb _instance = LocalDb._internal();
  factory LocalDb() => _instance;
  LocalDb._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'rampcheck.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,  -- local id
            remote_id INTEGER,                     -- server id
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            priority TEXT NOT NULL,                -- e.g. Low/Medium/High
            status TEXT NOT NULL,                  -- e.g. Open/InProgress/Closed
            user_id INTEGER,
            updated_at TEXT NOT NULL,              -- ISO string
            sync_state TEXT NOT NULL               -- 'clean' | 'dirty' | 'deleted' | 'conflict'
          )
        ''');

        //audit log
        await db.execute('''
          CREATE TABLE audit_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            entity TEXT NOT NULL,
            entity_id TEXT,
            details TEXT,
            ts TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }
}