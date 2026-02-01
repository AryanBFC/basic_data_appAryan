import 'dart:convert';
import '../domain/job.dart';
import 'jobs_repository.dart';
import '../api_client.dart';

class SyncService {
  final JobsRepository _repo;
  final ApiClient _api;

  SyncService(this._repo, this._api);

  /// Push local dirty changes to server, then pull server state and merge.
  Future<void> syncAll() async {
    // 1) Push local dirty jobs
    final dirty = await _repo.listDirty();
    for (final job in dirty) {
      try {
        if (job.syncState == 'deleted') {
          // Optional: if you implement DELETE server-side
          // await _api.deleteLog(job.remoteId!);
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
          result = await _api.createLog(
            title: job.title,
            description: job.description,
            priority: job.priority,
            status: job.status,
            userId: job.userId,
          );
        } else {
          result = await _api.updateLog(
            remoteId: job.remoteId!,
            payload: payload,
          );
        }

        // Mark local as clean and attach remote id
        final updated = job.copyWith(
          remoteId: result['id'] as int?,
          updatedAt: result['updated_at'] ?? job.updatedAt,
          syncState: 'clean',
        );
        await _repo.updateLocal(updated);
      } catch (e) {
        // Keep dirty state; you might log an audit event for failure
        await _repo.logAudit('sync_push_error', 'job', entityId: '${job.id}', details: e.toString());
      }
    }

    // 2) Pull from server and merge
    try {
      final serverLogs = await _api.listLogs();
      for (final s in serverLogs) {
        await _repo.upsertFromServer(s);
      }
    } catch (e) {
      await _repo.logAudit('sync_pull_error', 'job', details: e.toString());
    }
  }
}