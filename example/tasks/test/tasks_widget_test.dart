import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/app_shell/presentation/components/tasks_app.dart';

import 'nodus_test_harness.g.dart';

void main() {
  final accountId = LocalId<Account>('00000000-0000-0000-0000-000000000001');

  Future<TasksExampleEntityGraph> openGraph() async =>
      (await TasksExampleTestHarness.open(accountId: accountId)).entityGraph;

  Future<void> pumpTasks(
    WidgetTester tester,
    TasksExampleEntityGraph graph, {
    String? initialLocation,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TasksExample(
        entityGraph: graph,
        initialLocation: initialLocation,
        closeEntityGraphOnDispose: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeGraph(
    WidgetTester tester,
    TasksExampleEntityGraph graph,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(graph.close);
  }

  testWidgets(
    'Given a compact Tasks app, When a task is created, completed, and archived, Then production UI and generated state stay connected',
    (tester) async {
      final graph = await openGraph();
      await pumpTasks(tester, graph);

      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byKey(const Key('newTaskButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('taskTitleField')),
        'Publish architecture example',
      );
      await tester.enterText(
        find.byKey(const Key('taskDescriptionField')),
        'Keep the example focused on task behavior.',
      );
      await tester.ensureVisible(find.byKey(const Key('saveTaskButton')));
      await tester.tap(find.byKey(const Key('saveTaskButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('taskDetails')), findsOneWidget);
      expect(find.text('Publish architecture example'), findsOneWidget);
      await tester.tap(find.byKey(const Key('completeSelectedTaskButton')));
      await tester.pumpAndSettle();
      expect(find.text('done'), findsOneWidget);
      await tester.tap(find.byKey(const Key('archiveSelectedTaskButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('taskArchivedChip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tasksDestination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter:archived')));
      await tester.pumpAndSettle();
      expect(find.text('Publish architecture example'), findsOneWidget);

      final tasks = await TaskList.archived(
        graph,
      ).useAll((items) => List<Task>.of(items));
      final activity = await TaskActivityList.all(
        graph,
      ).useAll((items) => List<TaskActivity>.of(items));
      expect(tasks.single.isArchived, isTrue);
      expect(
        activity.map((event) => event.operation),
        containsAll([
          ActivityOperation.created,
          ActivityOperation.action('complete'),
          ActivityOperation.archived,
        ]),
      );
      await closeGraph(tester, graph);
    },
  );

  testWidgets(
    'Given an expanded task deep link, When it opens, Then navigation, list, and detail adapt without duplicating state',
    (tester) async {
      final graph = await openGraph();
      final task = await graph.tasks.create(
        title: 'Inspect the split view',
        description: null,
        projectId: null,
        priority: TaskPriority.normal,
        dueAt: null,
      );
      await graph.flushLocal();

      await pumpTasks(
        tester,
        graph,
        initialLocation: TaskDetailsRoute(task.id).location,
        size: const Size(1100, 800),
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.byKey(const Key('tasksList')), findsOneWidget);
      expect(find.byKey(const Key('taskDetails')), findsOneWidget);
      expect(find.text('Inspect the split view'), findsNWidgets(2));
      await closeGraph(tester, graph);
    },
  );

  testWidgets(
    'Given a medium window, When Tasks opens, Then it uses a compact navigation rail',
    (tester) async {
      final graph = await openGraph();
      await pumpTasks(tester, graph, size: const Size(700, 800));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(find.byType(NavigationBar), findsNothing);
      await closeGraph(tester, graph);
    },
  );

  testWidgets(
    'Given durable offline work, When Tasks opens, Then the sync badge makes the queue visible',
    (tester) async {
      final graph = await openGraph();
      await graph.tasks.create(title: 'Visible offline work');
      await graph.flushLocal();

      await pumpTasks(tester, graph);

      final badge = tester.widget<Badge>(
        find.byKey(const Key('syncQueueBadge')),
      );
      expect(badge.isLabelVisible, isTrue);
      expect(find.byKey(const Key('openSyncCenterButton')), findsOneWidget);
      await closeGraph(tester, graph);
    },
  );
}
