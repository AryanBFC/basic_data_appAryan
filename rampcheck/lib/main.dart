import 'package:flutter/material.dart';
import 'api_client.dart';
import 'data/jobs_repository.dart';
import 'data/sync_service.dart';
import 'domain/job.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

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
    setState(() { loading = true; error = null; });
    try {
      final result = await api.login(userController.text.trim(), passController.text.trim());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LogsPage(user: result['user'] as Map<String, dynamic>)),
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
          TextField(controller: userController, decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 8),
          TextField(controller: passController, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
          const SizedBox(height: 16),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          FilledButton(onPressed: loading ? null : _login, child: loading ? const CircularProgressIndicator() : const Text('Login')),
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

class _LogsPageState extends State<LogsPage> {
  final repo = JobsRepository();
  final api = ApiClient();
  late final SyncService sync = SyncService(repo, api);

  late Future<List<Job>> _future;

  @override
  void initState() {
    super.initState();
    _future = repo.listAll(); // Local-first => fast UI
  }

  Future<void> _refreshFromLocal() async {
    final items = await repo.listAll();
    setState(() {
      _future = Future.value(items);
    });
  }

  Future<void> _createLocalJob() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final job = Job(
      title: 'New Local Job',
      description: 'Created offline',
      priority: 'Medium',
      status: 'Open',
      userId: widget.user['id'] as int?,
      updatedAt: now,
      syncState: 'dirty',
    );
    await repo.insertLocal(job);
    await repo.logAudit('create_local', 'job', details: 'title=${job.title}');
    await _refreshFromLocal();
  }

  Future<void> _syncNow() async {
    final sw = Stopwatch()..start();
    await sync.syncAll();
    sw.stop();
    await repo.logAudit('sync', 'job', details: 'durationMs=${sw.elapsedMilliseconds}');
    await _refreshFromLocal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync complete in ${sw.elapsedMilliseconds} ms')),
    );
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
          if (jobs.isEmpty) return const Center(child: Text('No jobs yet. Create one.'));

          return ListView.separated(
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final j = jobs[i];
              final idLabel = j.remoteId != null ? '#${j.remoteId}' : '(local)';
              final dirtyBadge = j.syncState != 'clean' ? ' • ${j.syncState.toUpperCase()}' : '';
              return ListTile(
                title: Text('${j.title} $dirtyBadge'),
                subtitle: Text('$idLabel • ${j.priority} • ${j.status}'),
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