import 'package:sqflite/sqflite.dart';
import '../domain/job.dart';
import 'local_db.dart';

class JobsRepository {
  final LocalDb _dbProvider = LocalDb();

  Future<List<Job>> listAll() async {
    final db = await _dbProvider.database;
    final rows = await db.query('jobs', orderBy: 'id DESC');
    return rows.map(Job.fromRow).toList();
    //Local-first read keeps UI <300ms
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
    //Find by remote_id
    final existing = await db.query('jobs',
        where: 'remote_id = ?', whereArgs: [serverJson['id']]);

    final row = {
      'remote_id': serverJson['id'],
      'title': serverJson['title'],
      'description': serverJson['description'],
      'priority': serverJson['priority'],
      'status': serverJson['status'],
      'user_id': serverJson['user_id'],
      'updated_at': serverJson['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'clean',
    };

    if (existing.isEmpty) {
      await db.insert('jobs', row);
    } else {
      await db.update('jobs', row, where: 'remote_id = ?', whereArgs: [serverJson['id']]);
    }
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
}