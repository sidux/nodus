import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodus/nodus_sqlite.dart';
import 'package:tasks_example/nodus.g.dart';

void main() {
  final accountId = LocalId<Account>('00000000-0000-0000-0000-000000000001');

  Future<TasksExampleEntityGraph> openGraph(
    PushPullSyncAdapter server, {
    QueryExecutor? executor,
  }) => TasksExampleEntityGraph.open(
    accountId: accountId,
    executor: executor ?? openNodusInMemoryExecutor(),
    syncAdapters: TasksExampleSyncAdapters(supabase: server),
    autoSync: false,
  );

  /// A synchronized task, retained like a visible row keeps it.
  Future<Task> retainedTask(TasksExampleEntityGraph graph) async {
    final created = await graph.tasks.create(title: 'Write the report');
    final lease = (await graph.tasks.loadById(created.id))!;
    addTearDown(lease.release);
    await graph.sync();
    return lease.value;
  }

  test('Given a completion the server keeps answering with a version conflict, '
      'When the rebase retries are spent, Then the completion is undone and '
      'the conflict stays typed until acknowledged', () async {
    final server = _ConflictingCompletions();
    final graph = await openGraph(server);
    addTearDown(graph.close);
    final task = await retainedTask(graph);

    await task.complete();
    expect(task.status, TaskStatus.done);
    await graph.sync();

    expect(server.conflicts, 3);
    expect(task.status, TaskStatus.todo);
    expect(task.completedAt, isNull);
    final refused = graph.syncQueue.items.single as PushSyncWorkItem;
    expect(refused.status, SyncWorkStatus.conflict);
    expect(refused.lastFailure, isA<ConflictSyncWorkFailure>());
    expect(refused.operation.patch.toWire()['status'], TaskStatus.done.name);
    expect(graph.syncQueue.state.value.phase, SyncPhase.needsAttention);

    await graph.syncQueue.acknowledge(refused);

    expect(graph.syncQueue.items, isEmpty);
    expect(graph.syncQueue.state.value.phase, SyncPhase.idle);
    expect(task.status, TaskStatus.todo);
  });

  test(
    'Given an edit queued after a completion that keeps conflicting, When '
    'the completion is refused, Then the edit is kept and synchronized',
    () async {
      final server = _ConflictingCompletions();
      final graph = await openGraph(server);
      addTearDown(graph.close);
      final task = await retainedTask(graph);

      await task.complete();
      await (task.beginEdit()..title = 'Write the final report').save();
      await graph.sync();

      expect(task.status, TaskStatus.todo);
      expect(task.title, 'Write the final report');
      final record = server.records.recordFor('Task', task.id.value)!;
      expect(record['status'], TaskStatus.todo.name);
      expect(record['title'], 'Write the final report');
      expect(graph.syncQueue.items.map((item) => item.status), [
        SyncWorkStatus.conflict,
      ]);
    },
  );

  test(
    'Given a store where an earlier runtime left a refused conflict visible, '
    'When the graph opens again, Then the refused change is undone',
    () async {
      final directory = await Directory.systemTemp.createTemp('nodus_sync');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/tasks.sqlite');
      QueryExecutor store() =>
          NativeDatabase(file, setup: installNodusSqlFunctions);
      final server = _ConflictingCompletions();
      final earlier = await openGraph(server, executor: store());
      final task = await retainedTask(earlier);
      await task.complete();
      await earlier.sync();
      await earlier.close();
      final legacy = TasksExampleDatabase(store());
      await legacy.customStatement(
        "update tasks set status = 'done' where id = ?",
        [task.id.value],
      );
      await legacy.close();

      final graph = await openGraph(server, executor: store());
      addTearDown(graph.close);
      final reopened = (await graph.tasks.loadById(task.id))!;
      addTearDown(reopened.release);

      expect(reopened.value.status, TaskStatus.todo);
      expect(graph.syncQueue.items.map((item) => item.status), [
        SyncWorkStatus.conflict,
      ]);
    },
  );

  test('Given pending work, When the app tries to acknowledge it, Then the '
      'queue refuses and keeps it', () async {
    final graph = await openGraph(_ConflictingCompletions());
    addTearDown(graph.close);
    await graph.tasks.create(title: 'Write the report');
    final pending = graph.syncQueue.items.first;

    await expectLater(
      graph.syncQueue.acknowledge(pending),
      throwsArgumentError,
    );
    expect(graph.syncQueue.items, contains(pending));
  });
}

/// The server, answering every task completion with a version conflict.
final class _ConflictingCompletions implements PushPullSyncAdapter {
  final records = InMemorySyncBackend.graph(
    definition: TasksExampleMetadata.supabaseSyncDefinition,
  );
  var conflicts = 0;

  @override
  EntityGraphDefinition get definition => records.definition;

  @override
  Future<PushResult> push(PushSyncWorkItem item) async {
    final operation = item.operation;
    if (operation is PatchPushOperation &&
        operation.patch.toWire()['status'] == TaskStatus.done.name) {
      conflicts++;
      throw const VersionConflictException();
    }
    return records.push(item);
  }

  @override
  Future<PullResult> pull({required ServerSequence afterSequence}) =>
      records.pull(afterSequence: afterSequence);
}
