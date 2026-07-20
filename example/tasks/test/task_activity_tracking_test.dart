import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_example/nodus.g.dart';

import 'nodus_test_harness.g.dart';

void main() {
  final accountId = LocalId<Account>('00000000-0000-0000-0000-000000000001');

  Future<TasksExampleEntityGraph> openGraph({
    InMemorySyncBackend? backend,
    Clock clock = const _FixedClock(),
    bool autoSync = false,
  }) async => (await TasksExampleTestHarness.open(
    accountId: accountId,
    supabase: backend,
    autoSync: autoSync,
    clock: clock,
  )).entityGraph;

  test(
    'Given one graph transaction, When a nested aggregate transaction runs, Then both join one durable batch',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);

      late TaskProject project;
      late Task task;
      await graph.transaction(() async {
        project = await graph.taskProjects.create(title: 'Nested batch');
        await graph.transaction(() async {
          task = await graph.tasks.create(
            title: 'Joined mutation',
            projectId: project.id,
          );
          await task.complete();
        });
      });

      expect(task.projectId, project.id);
      expect(task.status, TaskStatus.done);
      expect(graph.persistenceFailures, isEmpty);
    },
  );

  test(
    'Given an active graph transaction, When unrelated asynchronous work mutates, Then it cannot join the batch',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);
      final transactionStarted = Completer<void>();
      final releaseTransaction = Completer<void>();

      final transaction = graph.transaction(() async {
        await graph.tasks.create(title: 'Owned transaction');
        transactionStarted.complete();
        await releaseTransaction.future;
      });
      await transactionStarted.future;

      try {
        await expectLater(
          graph.tasks.create(title: 'Unrelated mutation'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('owned by another asynchronous flow'),
            ),
          ),
        );
      } finally {
        releaseTransaction.complete();
        await transaction;
      }

      final tasks = await TaskList.all(
        graph,
      ).useAll((items) => List<Task>.of(items));
      expect(tasks.map((task) => task.title), ['Owned transaction']);
    },
  );

  test(
    'Given a tracked task, When it changes, Then entity state and generated activity commit together',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);

      final task = await graph.tasks.create(
        title: 'Ship the Tasks example',
        description: 'Exercise generated activity tracking.',
        projectId: null,
        priority: TaskPriority.high,
        dueAt: DateTime.utc(2026, 8, 1),
      );
      await task.complete();
      await task.complete();
      await task.archive();
      await graph.flushLocal();

      expect(task.status, TaskStatus.done);
      expect(task.completedAt, DateTime.utc(2026, 7, 19, 12));
      expect(task.archivedAt, DateTime.utc(2026, 7, 19, 12));
      final activity = await TaskActivityList.forTask(
        graph,
        task.id,
        orderBy: TaskActivityFields.occurredAt.ascending(),
      ).useAll((items) => List<TaskActivity>.of(items));
      expect(activity.map((event) => event.operation), [
        ActivityOperation.created,
        ActivityOperation.action('complete'),
        ActivityOperation.archived,
      ]);
      expect(activity.map((event) => event.label), everyElement(task.title));
      expect(graph.syncQueue.items, isNotEmpty);
    },
  );

  test(
    'Given one generated mutation draft, When it creates and edits a task, Then typed fields and scope movement commit atomically',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);
      final project = await graph.taskProjects.create(title: 'Draft target');

      final createDraft = graph.tasks.beginCreate()
        ..title = 'Created from one draft'
        ..description = null
        ..priority = TaskPriority.normal
        ..dueAt = null
        ..projectId = null;
      final task = await createDraft.save();

      final editDraft = task.beginEdit()
        ..title = 'Edited from one draft'
        ..description = 'One save owns both actions.'
        ..priority = TaskPriority.high
        ..dueAt = DateTime.utc(2026, 9, 1)
        ..projectId = project.id;
      final saved = await editDraft.save();

      expect(saved, same(task));
      expect(task.title, 'Edited from one draft');
      expect(task.description, 'One save owns both actions.');
      expect(task.priority, TaskPriority.high);
      expect(task.projectId, project.id);
      expect(editDraft.isConsumed, isTrue);
    },
  );

  test(
    'Given a task owner, When setCollaborator is called directly, Then access and activity are durable',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);
      final task = await graph.tasks.create(
        title: 'Review shared plan',
        description: null,
        projectId: null,
        priority: TaskPriority.normal,
        dueAt: null,
      );
      final collaboratorId = LocalId<Account>(
        '10000000-0000-4000-8000-000000000002',
      );

      await task.setCollaborator(collaboratorId, active: true);
      await graph.flushLocal();

      expect(
        graph.syncQueue.items,
        contains(
          isA<SyncWorkItem>().having(
            (item) => item.kind,
            'kind',
            SyncWorkKind.semanticCommand,
          ),
        ),
      );
      final activity = await TaskActivityList.forTask(
        graph,
        task.id,
      ).useAll((items) => List<TaskActivity>.of(items));
      expect(
        activity.any(
          (event) => event.operation == ActivityOperation.collaborationChanged,
        ),
        isTrue,
      );
    },
  );

  test(
    'Given project-scoped tasks, When order and project change, Then generated ordering remains canonical',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);
      final firstProject = await graph.taskProjects.create(title: 'Launch');
      final secondProject = await graph.taskProjects.create(title: 'Later');
      final first = await graph.tasks.create(
        title: 'First',
        description: null,
        projectId: firstProject.id,
        priority: TaskPriority.normal,
        dueAt: null,
      );
      final second = await graph.tasks.create(
        title: 'Second',
        description: null,
        projectId: firstProject.id,
        priority: TaskPriority.normal,
        dueAt: null,
      );
      final third = await graph.tasks.create(
        title: 'Third',
        description: null,
        projectId: firstProject.id,
        priority: TaskPriority.normal,
        dueAt: null,
      );

      await graph.tasks.moveBefore(third.id, first.id);
      await second.moveToProject(projectId: secondProject.id);
      await graph.flushLocal();

      final launchTasks = await TaskList.forProject(
        graph,
        firstProject.id,
      ).useAll((items) => List<Task>.of(items));
      final laterTasks = await TaskList.forProject(
        graph,
        secondProject.id,
      ).useAll((items) => List<Task>.of(items));
      expect(launchTasks.map((task) => task.title), ['Third', 'First']);
      expect(laterTasks, [same(second)]);
    },
  );

  test(
    'Given a deleted task, When ordinary and repair queries run, Then tombstone visibility is explicit',
    () async {
      final graph = await openGraph();
      addTearDown(graph.close);
      final task = await graph.tasks.create(title: 'Recoverable task');

      await task.remove();
      await graph.flushLocal();

      final ordinary = await TaskList.all(
        graph,
      ).useAll((items) => List<Task>.of(items));
      final repair = await TaskList.all(
        graph,
        tombstones: TombstoneVisibility.only,
      ).useAll((items) => List<Task>.of(items));
      expect(ordinary, isEmpty);
      expect(repair, [same(task)]);
    },
  );

  test(
    'Given queued local work, When synchronization runs, Then the generated backend receives the task graph',
    () async {
      final backend = InMemorySyncBackend.graph(
        definition: TasksExampleMetadata.supabaseSyncDefinition,
      );
      final graph = await openGraph(backend: backend);
      addTearDown(graph.close);
      final task = await graph.tasks.create(
        title: 'Synchronize me',
        description: null,
        projectId: null,
        priority: TaskPriority.low,
        dueAt: null,
      );

      await graph.sync();

      expect(graph.syncQueue.items, isEmpty);
      expect(
        backend.recordFor('Task', task.id.value)!['title'],
        'Synchronize me',
      );
    },
  );

  test(
    'Given synchronized tracked activity, When another graph pulls it, Then remote source replay does not duplicate history',
    () async {
      final backend = InMemorySyncBackend.graph(
        definition: TasksExampleMetadata.supabaseSyncDefinition,
      );
      final source = await openGraph(backend: backend);
      addTearDown(source.close);
      final task = await source.tasks.create(
        title: 'Pull activity once',
        description: null,
        projectId: null,
        priority: TaskPriority.normal,
        dueAt: null,
      );
      await task.complete();
      await source.sync();
      final sourceActivity = await TaskActivityList.forTask(
        source,
        task.id,
      ).useAll((items) => List<TaskActivity>.of(items));
      expect(sourceActivity, hasLength(2));
      expect(
        sourceActivity.every(
          (event) => backend.recordFor('TaskActivity', event.id.value) != null,
        ),
        isTrue,
      );
      await source.close();

      final replica = await openGraph(backend: backend, autoSync: true);
      addTearDown(replica.close);
      await replica.sync();

      final activity = await TaskActivityList.forTask(
        replica,
        task.id,
        orderBy: TaskActivityFields.occurredAt.ascending(),
      ).useAll((items) => List<TaskActivity>.of(items));
      expect(activity.map((event) => event.operation), [
        ActivityOperation.created,
        ActivityOperation.action('complete'),
      ]);
    },
  );
}

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 7, 19, 12);
}
