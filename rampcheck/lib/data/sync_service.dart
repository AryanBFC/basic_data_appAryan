import '../domain/job.dart';
import 'jobs_repository.dart';
import '../api_client.dart';

class SyncService {
  final JobsRepository _repo;
  final ApiClient _api;

  //prevent concurrent syncs
  static bool _isSyncing = false;

  SyncService(this._repo, this._api);

  Future<void> syncAll() async {
    //if a sync is already running skip this invocation
    if (_isSyncing) {
      await _repo.logAudit('sync_skipped', 'job', details: 'concurrent invocation skipped');
      return;
    }
    _isSyncing = true;
    try {
      await _repo.ensureIndexes(); //unique index on remote_id

      //push local dirty jobs (create/update)
      final dirty = await _repo.listDirty();
      for (final job in dirty) {
        try {
          if (job.syncState == 'deleted') {
            continue;
          }

          final payload = {
            'title': job.title,
            'description': job.description,
            'priority': job.priority,
            'status': job.status,
            'user_id': job.userId,
          };

          Map<String, dynamic> result;
          if (job.remoteId == null) {
            //CREATE on server
            result = await _api.createLog(
              title: job.title,
              description: job.description,
              priority: job.priority,
              status: job.status,
              userId: job.userId,
            );
          } else {
            //UPDATE on server
            result = await _api.updateLog(
              remoteId: job.remoteId!,
              payload: payload,
            );
          }

          final serverId = _asInt(result['id']);
          final serverUpdatedAt =
              (result['updated_at'] as String?) ?? DateTime.now().toUtc().toIso8601String();

          //immediately links this local row to the server id and marks it clean
          if (job.id != null && serverId != null) {
            await _repo.markAsSynced(
              localId: job.id!,
              remoteId: serverId,
              serverUpdatedAt: serverUpdatedAt,
            );
          } else {
            final updated = job.copyWith(
              remoteId: serverId,
              updatedAt: serverUpdatedAt,
              syncState: 'clean',
            );
            await _repo.updateLocal(updated);
          }
        } catch (e) {
          await _repo.logAudit(
            'sync_push_error',
            'job',
            entityId: '${job.id}',
            details: e.toString(),
          );
        }
      }

      //pull from server and merge
      try {
        final serverLogs = await _api.listLogs();
        for (final s in serverLogs) {
          await _repo.upsertFromServer(s);
        }
      } catch (e) {
        await _repo.logAudit('sync_pull_error', 'job', details: e.toString());
      }
    } finally {
      _isSyncing = false;
    }
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