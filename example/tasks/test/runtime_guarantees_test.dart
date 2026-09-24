import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodus/nodus_testing.dart';
import 'package:tasks_example/nodus.g.dart';

import 'nodus_test_harness.g.dart';

void main() {
  late InMemorySyncBackend backend;
  late NodusTestClock clock;
  late TasksExampleEntityGraph graph;

  setUp(() async {
    backend = InMemorySyncBackend.graph(
      definition: TasksExampleMetadata.supabaseSyncDefinition,
    );
    clock = NodusTestClock();
    graph = (await TasksExampleTestHarness.open(
      supabase: backend,
      clock: clock,
    )).entityGraph;
    addTearDown(graph.close);
  });

  Future<Task> createTask(String title) => graph.tasks.create(
    title: title,
    description: null,
    projectId: null,
    priority: TaskPriority.normal,
    dueAt: null,
  );

  void failPushes(int count) {
    var remaining = count;
    backend.pushFault = (_) => remaining-- > 0
        ? const RetryableSyncException(code: 'offline', message: 'Offline.')
        : null;
  }

  test(
    'Given a push backing off, When later work synchronizes, Then it waits behind the head',
    () async {
      failPushes(1);
      final first = await createTask('First');
      await graph.sync();

      final second = await createTask('Second');
      await graph.sync();

      expect(backend.recordFor('Task', first.id.value), isNull);
      expect(backend.recordFor('Task', second.id.value), isNull);

      clock.advance(const Duration(hours: 1));
      await graph.sync();

      expect(backend.recordFor('Task', first.id.value)?['title'], 'First');
      expect(backend.recordFor('Task', second.id.value)?['title'], 'Second');
      expect(graph.syncQueue.items, isEmpty);
    },
  );

  test(
    'Given a queued edit, When a later edit follows a command on that entity, Then it queues after the command',
    () async {
      await graph.taskProjects.create(title: 'Sibling');
      final project = await graph.taskProjects.create(title: 'Draft');
      final rename = project.beginEdit()..title = 'Renamed';
      await rename.save();
      await graph.taskProjects.prepend(project.id);
      final retitle = project.beginEdit()..title = 'Final';
      await retitle.save();

      final pushes = graph.syncQueue.items
          .whereType<PushSyncWorkItem>()
          .where((item) => item.operation.identity.rawId == project.id.value)
          .toList();
      expect(pushes.map((item) => item.pushKind), [
        PushSyncWorkKind.statePatch,
        PushSyncWorkKind.semanticCommand,
        PushSyncWorkKind.statePatch,
      ]);
      expect(pushes.first.operation.patch.toWire()['title'], 'Renamed');
      expect(pushes.last.operation.patch.toWire()['title'], 'Final');

      await graph.sync();
      expect(graph.syncQueue.items, isEmpty);
      expect(
        backend.recordFor('TaskProject', project.id.value)?['title'],
        'Final',
      );
    },
  );

  test(
    'Given an earlier failed save, When an unrelated transaction and close run, Then neither rethrows it',
    () async {
      final missingProject = LocalId<TaskProject>(
        '00000000-0000-7000-8000-000000000099',
      );
      await expectLater(
        graph.tasks.create(
          title: 'Dangling',
          description: null,
          projectId: missingProject,
          priority: TaskPriority.normal,
          dueAt: null,
        ),
        throwsA(anything),
      );
      expect(graph.persistenceFailures, isNotEmpty);

      final task = await graph.transaction(() => createTask('Unrelated'));

      expect(task.title, 'Unrelated');
      await graph.close();
    },
  );

  test(
    'Given an action guard, When it rejects a call, Then nothing changes',
    () async {
      final task = await createTask('Open');

      await expectLater(task.reopen(), throwsA(isA<ActionGuardException>()));
      expect(task.status, TaskStatus.todo);

      await task.complete();
      await task.reopen();
      expect(task.status, TaskStatus.todo);
    },
  );

  test(
    'Given a rejected pull, When sync runs again, Then a fresh pull replaces it',
    () async {
      var rejections = 1;
      backend.pullFault = () => rejections-- > 0
          ? const RejectedSyncException.protocol(message: 'Bad page.')
          : null;

      await graph.sync();
      expect(graph.syncQueue.items, hasLength(1));

      await graph.sync();
      expect(graph.syncQueue.items, isEmpty);
    },
  );

  test(
    'Given an undecodable queued operation, When sync runs, Then it is quarantined and later work pushes',
    () async {
      final executor = NativeDatabase.memory();
      final direct = await TasksExampleEntityGraph.open(
        accountId: LocalId('00000000-0000-0000-0000-000000000002'),
        executor: executor,
        syncAdapters: TasksExampleSyncAdapters(supabase: backend),
        autoSync: false,
      );
      addTearDown(direct.close);
      Future<Task> create(String title) => direct.tasks.create(
        title: title,
        description: null,
        projectId: null,
        priority: TaskPriority.normal,
        dueAt: null,
      );

      await create('Corrupted');
      await executor.runCustom(
        "update local_entity_sync_work set payload = '{}' "
        "where direction = 'push'",
      );
      final healthy = await create('Healthy');

      await direct.sync();

      expect(backend.recordFor('Task', healthy.id.value)?['title'], 'Healthy');
    },
  );

  test(
    'Given a column subquery filter, When the selected rows change, Then the query follows them',
    () async {
      final home = await graph.taskProjects.create(title: 'Home');
      final work = await graph.taskProjects.create(title: 'Work');
      await graph.taskProjects.create(title: 'Empty');
      final call = await graph.tasks.create(
        title: 'Call',
        description: null,
        projectId: work.id,
        priority: TaskPriority.high,
        dueAt: null,
      );
      await graph.tasks.create(
        title: 'Loose',
        description: null,
        projectId: null,
        priority: TaskPriority.high,
        dueAt: null,
      );
      await graph.tasks.create(
        title: 'Chores',
        description: null,
        projectId: home.id,
        priority: TaskPriority.low,
        dueAt: null,
      );
      LocalEntityQuery<TaskProject> highPriorityProjects() =>
          graph.taskProjects.query(
            where: TaskProjectFields.id.isInColumn(
              graph.tasks.column(
                TaskFields.projectId,
                where: TaskFields.priority.equals(TaskPriority.high),
              ),
            ),
          );
      final projects = highPriorityProjects();
      addTearDown(projects.dispose);
      final rebuilt = highPriorityProjects();
      addTearDown(rebuilt.dispose);
      expect(rebuilt.sharesSelectionWith(projects), isTrue);
      final inMemoryOnly = LocalEntityQueryCache<TaskProject>(
        source: graph.taskProjects.all,
      );
      addTearDown(inMemoryOnly.dispose);
      expect(
        () => inMemoryOnly.acquire(EntityQuerySpec(where: projects.spec.where)),
        throwsUnsupportedError,
      );
      Future<List<String>> titles() async =>
          (await projects.loadAll()).map((project) => project.title).toList();

      expect(await titles(), ['Work']);

      await call.moveToProject(projectId: home.id);
      expect(await titles(), ['Home']);

      await call.archive();
      expect(await titles(), isEmpty);
    },
  );

  test(
    'Given settled queries, When an edit cannot affect one of them, Then only the affected query reloads',
    () async {
      final urgent = await createTask('Urgent');
      final someday = await createTask('Someday');
      Future<void> setPriority(Task task, TaskPriority priority) =>
          (task.beginEdit()..priority = priority).save();
      await setPriority(urgent, TaskPriority.high);

      LocalEntityQuery<Task> withPriority(TaskPriority priority) =>
          graph.tasks.query(where: TaskFields.priority.equals(priority));
      final high = withPriority(TaskPriority.high);
      final normal = withPriority(TaskPriority.normal);
      addTearDown(high.dispose);
      addTearDown(normal.dispose);
      final highStates = <EntityQueryState<Task>>[];
      final subscription = high.watchStates().listen(highStates.add);
      addTearDown(subscription.cancel);
      Future<List<String>> titles(LocalEntityQuery<Task> query) async =>
          (await query.loadAll()).map((task) => task.title).toList();
      expect(await titles(high), ['Urgent']);
      expect(await titles(normal), ['Someday']);
      highStates.clear();

      await setPriority(someday, TaskPriority.low);
      expect(await titles(normal), isEmpty);
      expect(highStates, isEmpty);

      await setPriority(someday, TaskPriority.high);
      expect(await titles(high), unorderedEquals(['Urgent', 'Someday']));
      expect(highStates, isNotEmpty);
    },
  );

  test(
    'Given many exact lookups, When they load together, Then one query serves them',
    () async {
      final reads = _TaskReadCounter();
      final direct = await TasksExampleEntityGraph.open(
        accountId: LocalId('00000000-0000-0000-0000-000000000003'),
        executor: NativeDatabase.memory().interceptWith(reads),
        syncAdapters: TasksExampleSyncAdapters(supabase: backend),
        autoSync: false,
      );
      addTearDown(direct.close);
      final titles = ['One', 'Two', 'Three'];
      final ids = [
        for (final title in titles)
          (await direct.tasks.create(
            title: title,
            description: null,
            projectId: null,
            priority: TaskPriority.normal,
            dueAt: null,
          )).id,
      ];
      final missing = direct.tasks.allocateId();

      reads.count = 0;
      final lookups = [
        for (final id in [...ids, missing]) direct.tasks.lookup(id),
      ];
      addTearDown(() {
        for (final lookup in lookups) {
          lookup.dispose();
        }
      });
      final values = await Future.wait(lookups.map((lookup) => lookup.load()));

      expect(values.map((task) => task?.title), ['One', 'Two', 'Three', null]);
      expect(reads.count, 1);
    },
  );

  test(
    'Given a paged query, When it loads exhaustively, Then the remainder takes one read',
    () async {
      final reads = _TaskReadCounter();
      final direct = await TasksExampleEntityGraph.open(
        accountId: LocalId('00000000-0000-0000-0000-000000000004'),
        executor: NativeDatabase.memory().interceptWith(reads),
        syncAdapters: TasksExampleSyncAdapters(supabase: backend),
        autoSync: false,
      );
      addTearDown(direct.close);
      await direct.transaction(() async {
        for (var index = 0; index < 120; index++) {
          await direct.tasks.create(
            title: 'Task $index',
            description: null,
            projectId: null,
            priority: TaskPriority.normal,
            dueAt: null,
          );
        }
      });

      reads.count = 0;
      final all = direct.tasks.query(pageSize: 50);
      addTearDown(all.dispose);

      expect(await all.loadAll(), hasLength(120));
      expect(reads.count, 2);
    },
  );

  test(
    'Given a live query, When a local write resolves, Then the query already shows it',
    () async {
      final open = graph.tasks.query(
        where: TaskFields.status.equals(TaskStatus.todo),
      );
      addTearDown(open.dispose);
      await open.loadAll();
      expect(open.items, isEmpty);

      final task = await createTask('Write report');
      expect(open.items.map((item) => item.title), ['Write report']);

      await task.complete();
      expect(open.items, isEmpty);
    },
  );
}

final class _TaskReadCounter extends QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.startsWith('select * from tasks ')) count++;
    return super.runSelect(executor, statement, args);
  }
}
