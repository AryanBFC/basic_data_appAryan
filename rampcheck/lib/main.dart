import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'api_client.dart';
import 'data/jobs_repository.dart';
import 'data/sync_service.dart';
import 'domain/job.dart';

//background sync for android
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      final repo = JobsRepository();
      final api = ApiClient();
      final sync = SyncService(repo, api);

      //full sync
      await sync.syncAll();
      return Future.value(true);
    } catch (_) {
      //returns false to show failure
      return Future.value(false);
    }
  });
}

//unique identifiers for background tasks
const String kPeriodicSyncTask = 'rampcheck_periodic_sync';

Future<void> _initBackgroundSync() async {
  if (!kIsWeb && Platform.isAndroid) {
    //initialise WorkManager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    //register periodic background sync task with network constraint
    await Workmanager().registerPeriodicTask(
      kPeriodicSyncTask,
      kPeriodicSyncTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //desktop DB init
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  
  //clean & enforce uniqueness before any sync
  final repo = JobsRepository();
  await repo.cleanupDuplicatesAndCreateUniqueIndex();


  //android background sync
  await _initBackgroundSync();

  runApp(const RampCheckApp());
}

class RampCheckApp extends StatelessWidget {
  const RampCheckApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RampCheck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final userController = TextEditingController(text: 'tech1');
  final passController = TextEditingController(text: 'P@ssw0rd!');
  final api = ApiClient();
  bool loading = false;
  String? error;

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result =
          await api.login(userController.text.trim(), passController.text.trim());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LogsPage(user: result['user'] as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('RampCheck - Login')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: userController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: loading ? null : _login,
                child: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Login'),
              ),
            ],
          ),
        ),
      );
}

class LogsPage extends StatefulWidget {
  final Map<String, dynamic> user;
  const LogsPage({super.key, required this.user});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> with WidgetsBindingObserver {
  final repo = JobsRepository();
  final api = ApiClient();
  late final SyncService sync = SyncService(repo, api);

  late Future<List<Job>> _future;
  static const _statusOptions = <String>['Open', 'In Progress', 'Closed'];

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = repo.listAll();

    _tryAutoSync();

    //listens for connectivity changes to auto-sync when network returns
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork =
          results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        _tryAutoSync();
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryAutoSync();
    }
  }

  Future<void> _tryAutoSync() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasNetwork =
          results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        await sync.syncAll();
        await _refreshFromLocal();
      }
    } catch (_) {
      //background auto-sync should never crash UI
    }
  }

  Future<void> _refreshFromLocal() async {
    final items = await repo.listAll();
    if (!mounted) return;
    setState(() {
      _future = Future.value(items);
    });
  }

  Future<void> _createLocalJob() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final job = Job(
      //id is auto - repo will return with id set
      remoteId: null,
      title: 'New Local Job',
      description: 'Created offline',
      priority: 'Medium',
      status: 'Open',
      userId: widget.user['id'] as int?,
      updatedAt: now,
      syncState: 'dirty',
    );
    final created = await repo.insertLocal(job);
    await repo.logAudit(
      'create_local',
      'job',
      entityId: (created.remoteId ?? created.id)?.toString(),
      details: 'title=${created.title}',
    );
    await _refreshFromLocal();

    _tryAutoSync();
  }

  Future<void> _syncNow() async {
    final sw = Stopwatch()..start();
    await sync.syncAll();
    sw.stop();
    await repo.logAudit(
      'sync',
      'job',
      details: 'durationMs=${sw.elapsedMilliseconds}',
    );
    await _refreshFromLocal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync complete in ${sw.elapsedMilliseconds} ms')),
    );
  }

  Future<void> _updateJob(
    Job job, {
    String? title,
    String? status,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = job.copyWith(
      title: title ?? job.title,
      status: status ?? job.status,
      updatedAt: now,
      syncState: 'dirty',
    );

    await repo.updateLocal(updated);

    await repo.logAudit(
      'update_local',
      'job',
      entityId: (updated.remoteId ?? updated.id)?.toString(),
      details: 'title=${updated.title};status=${updated.status}',
    );

    await _refreshFromLocal();

    _tryAutoSync();
  }

  Future<void> _renameJobDialog(Job job) async {
    final controller = TextEditingController(text: job.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename job'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Job title'),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != job.title) {
      await _updateJob(job, title: result);
    }
  }

  Future<void> _changeStatus(Job job, String status) async {
    await _updateJob(job, status: status);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(
        title: Text('Jobs - ${user['username']}'),
        actions: [
          IconButton(
            tooltip: 'Sync',
            onPressed: _syncNow,
            icon: const Icon(Icons.sync),
          )
        ],
      ),
      body: FutureBuilder<List<Job>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final jobs = snap.data ?? [];
          if (jobs.isEmpty) {
            return const Center(child: Text('No jobs yet. Create one.'));
          }

          return ListView.separated(
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final j = jobs[i];
              final idLabel =
                  j.remoteId != null ? '#${j.remoteId}' : '(local)';
              final dirtyBadge =
                  j.syncState != 'clean' ? ' • ${j.syncState.toUpperCase()}' : '';
              final isClosed = (j.status).toLowerCase() == 'closed';

              return ListTile(
                leading: Checkbox(
                  value: isClosed,
                  onChanged: (checked) async {
                    final nextStatus = (checked ?? false) ? 'Closed' : 'Open';
                    await _changeStatus(j, nextStatus);
                  },
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${j.title} $dirtyBadge',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isClosed
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit),
                      onPressed: () => _renameJobDialog(j),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Change status',
                      onSelected: (value) => _changeStatus(j, value),
                      itemBuilder: (context) => _statusOptions
                          .map(
                            (s) => PopupMenuItem(
                              value: s,
                              child: Text(s),
                            ),
                          )
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag,
                                color: isClosed ? Colors.green : Colors.grey),
                            const SizedBox(width: 4),
                            Text(j.status, style: const TextStyle(fontSize: 12)),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text('$idLabel • ${j.priority} • ${j.status}'),
                onTap: () => _renameJobDialog(j),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createLocalJob,
        icon: const Icon(Icons.add),
        label: const Text('New job'),
      ),
    );
  }
}