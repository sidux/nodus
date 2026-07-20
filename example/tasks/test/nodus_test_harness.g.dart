// GENERATED FILE. DO NOT EDIT.
// Test support for package:tasks_example/nodus.lock
// ignore_for_file: type=lint

import 'package:nodus/nodus_testing.dart';
import 'package:tasks_example/nodus.g.dart';

final class TasksExampleTestHarness {
  TasksExampleTestHarness._({
    required this.entityGraph,
    required this.clock,
    required this.supabase,
  });

  final TasksExampleEntityGraph entityGraph;
  final Clock clock;
  final InMemorySyncBackend supabase;

  static Future<TasksExampleTestHarness> open({
    LocalId<Account>? accountId,
    Clock? clock,
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    LocalEntityDiagnostics diagnostics = const NoopLocalEntityDiagnostics(),
    InMemorySyncBackend? supabase,
    bool autoSync = false,
  }) async {
    final resolvedAccountId =
        accountId ?? LocalId<Account>('00000000-0000-0000-0000-000000000001');
    final resolvedClock = clock ?? NodusTestClock();
    final resolvedSupabase =
        supabase ??
        InMemorySyncBackend.graph(
          definition: TasksExampleMetadata.supabaseSyncDefinition,
        );
    final entityGraph = await TasksExampleEntityGraph.openInMemory(
      accountId: resolvedAccountId,
      clock: resolvedClock,
      idGenerator: idGenerator,
      diagnostics: diagnostics,
      autoSync: autoSync,
      supabaseBackend: resolvedSupabase,
    );
    return TasksExampleTestHarness._(
      entityGraph: entityGraph,
      clock: resolvedClock,
      supabase: resolvedSupabase,
    );
  }

  Future<void> close() => entityGraph.close();
}
