import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tasks_example/nodus.g.dart';

final class TasksBootstrap {
  const TasksBootstrap._();

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _allowInMemoryDemo = bool.fromEnvironment(
    'ALLOW_IN_MEMORY_DEMO',
  );
  static const _localAccountId = '00000000-0000-0000-0000-000000000001';

  static Future<TasksExampleEntityGraph> open() async {
    final useSupabase = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
    if (!useSupabase && !_allowInMemoryDemo) {
      throw StateError(
        'Provide SUPABASE_URL and SUPABASE_ANON_KEY, or explicitly enable '
        'the ephemeral demo with ALLOW_IN_MEMORY_DEMO=true.',
      );
    }
    if (useSupabase) {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseAnonKey,
      );
      final client = Supabase.instance.client;
      var user = client.auth.currentUser;
      if (user == null) {
        final response = await client.auth.signInAnonymously();
        user = response.user;
      }
      if (user == null) {
        throw StateError('Supabase authentication did not return a user.');
      }
      return TasksExampleEntityGraph.openSupabase(
        accountId: parseLocalId<Account>(user.id),
        client: client,
        autoSync: true,
      );
    }
    final entityGraph = await TasksExampleEntityGraph.openInMemory(
      accountId: LocalId<Account>(_localAccountId),
      autoSync: false,
    );
    await seedTasksDemo(entityGraph);
    return entityGraph;
  }
}

/// Populates only the explicit ephemeral demo with a small offline workspace.
///
/// Every item goes through the same generated APIs as production UI. The
/// unsynchronized queue and activity trail therefore start with meaningful
/// state for an evaluator instead of an empty screen.
Future<void> seedTasksDemo(TasksExampleEntityGraph entityGraph) async {
  if (entityGraph.taskProjects.all.isNotEmpty) return;

  final launch = await entityGraph.taskProjects.create(title: 'Nodus launch');
  final followUp = await entityGraph.taskProjects.create(
    title: 'After the hackathon',
  );
  final now = entityGraph.nowUtc();

  await launch
      .tasks(entityGraph)
      .createFirst(
        title: 'Define the domain once',
        description:
            'This task, its local table, sync protocol, query API, and route data '
            'all come from one entity declaration.',
        priority: TaskPriority.high,
        dueAt: now.add(const Duration(days: 1)),
      );
  final generated = await launch
      .tasks(entityGraph)
      .create(
        title: 'Inspect generated infrastructure',
        description:
            'Open Sync to see durable offline work waiting for synchronization.',
        priority: TaskPriority.high,
        dueAt: now.add(const Duration(days: 2)),
      );
  await generated.start();

  final submission = await launch
      .tasks(entityGraph)
      .create(
        title: 'Submit the hackathon demo',
        description:
            'Typed actions update the stable entity immediately and commit the '
            'local projection with its sync intent atomically.',
        dueAt: now.add(const Duration(days: 4)),
      );
  await submission.complete();

  final archived = await followUp
      .tasks(entityGraph)
      .create(
        title: 'Explore custom sync connectors',
        description: 'Nodus infers the graph while the adapter owns transport.',
        priority: TaskPriority.low,
      );
  await archived.archive();
  await entityGraph.flushLocal();
}
