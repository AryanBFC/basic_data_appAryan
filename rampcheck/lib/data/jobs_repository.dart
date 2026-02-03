import 'package:sqflite/sqflite.dart';
import '../domain/job.dart';
import 'local_db.dart';

class JobsRepository {
  final LocalDb _dbProvider = LocalDb();
  Future<void> ensureIndexes() async {
    final db = await _dbProvider.database;
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_jobs_remote_id_unique '
      'ON jobs(remote_id) WHERE remote_id IS NOT NULL;',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_jobs_sync_state ON jobs(sync_state);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_jobs_updated_at ON jobs(updated_at);',
    );
  }

  Future<void> cleanupDuplicatesAndCreateUniqueIndex() async {
    final db = await _dbProvider.database;

    await db.transaction((txn) async {
      //find duplicate remote_id values 
      final dups = await txn.rawQuery('''
        SELECT remote_id, COUNT(*) as cnt
        FROM jobs
        WHERE remote_id IS NOT NULL
        GROUP BY remote_id
        HAVING COUNT(*) > 1
      ''');

      //for each duplicate remote_id, keeps the newest and deletes others
      for (final row in dups) {
        final int remoteId = (row['remote_id'] as int);

        //newest by updated_at DESC
        final newest = await txn.query(
          'jobs',
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          orderBy: 'updated_at DESC',
          limit: 1,
        );

        final allRows = await txn.query(
          'jobs',
          columns: ['id'],
          where: 'remote_id = ?',
          whereArgs: [remoteId],
        );

        if (newest.isEmpty) continue;
        final keepId = newest.first['id'] as int;

        for (final r in allRows) {
          final id = r['id'] as int;
          if (id == keepId) continue;
          await txn.delete('jobs', where: 'id = ?', whereArgs: [id]);
        }
      }

      try {
        await txn.execute('DROP INDEX IF EXISTS idx_jobs_remote_id_unique;');
      } catch (_) {}

      await txn.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_jobs_remote_id_unique '
        'ON jobs(remote_id) WHERE remote_id IS NOT NULL;',
      );

      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_jobs_sync_state ON jobs(sync_state);',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_jobs_updated_at ON jobs(updated_at);',
      );
    });
  }

  Future<List<Job>> listAll() async {
    final db = await _dbProvider.database;
    final rows = await db.query('jobs', orderBy: 'id DESC');
    return rows.map(Job.fromRow).toList();
  }

  Future<Job> insertLocal(Job job) async {
    final db = await _dbProvider.database;
    final id = await db.insert('jobs', job.toRow()..remove('id'));
    return job.copyWith(id: id);
  }

  Future<int> updateLocal(Job job) async {
    final db = await _dbProvider.database;
    return db.update('jobs', job.toRow()..remove('id'),
        where: 'id = ?', whereArgs: [job.id]);
  }

  Future<int> deleteLocal(int id) async {
    final db = await _dbProvider.database;
    return db.delete('jobs', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Job>> listDirty() async {
    final db = await _dbProvider.database;
    final rows = await db.query('jobs', where: 'sync_state != ?', whereArgs: ['clean']);
    return rows.map(Job.fromRow).toList();
  }

  Future<void> upsertFromServer(Map<String, dynamic> serverJson) async {
    final db = await _dbProvider.database;

    final int? remoteId = _asInt(serverJson['id']);
    if (remoteId == null) return;

    final row = {
      'remote_id': remoteId,
      'title': (serverJson['title'] ?? '').toString(),
      'description': (serverJson['description'] ?? '').toString(),
      'priority': (serverJson['priority'] ?? '').toString(),
      'status': (serverJson['status'] ?? '').toString(),
      'user_id': _asInt(serverJson['user_id']),
      'updated_at': (serverJson['updated_at'] as String?) ??
          DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'clean',
    };

    await db.insert(
      'jobs',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> markAsSynced({
    required int localId,
    required int remoteId,
    required String serverUpdatedAt,
  }) async {
    final db = await _dbProvider.database;
    return db.update(
      'jobs',
      {
        'remote_id': remoteId,
        'updated_at': serverUpdatedAt,
        'sync_state': 'clean',
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> logAudit(String type, String entity, {String? entityId, String? details}) async {
    final db = await _dbProvider.database;
    await db.insert('audit_events', {
      'event_type': type,
      'entity': entity,
      'entity_id': entityId,
      'details': details,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    try {
      return int.tryParse(v.toString());
    } catch (_) {
      return null;
    }
  }
}