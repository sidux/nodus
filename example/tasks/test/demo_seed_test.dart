import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_example/app_bootstrap.dart';
import 'package:tasks_example/nodus.g.dart';

import 'nodus_test_harness.g.dart';

void main() {
  test(
    'Given the ephemeral showcase, When it is seeded twice, Then production APIs create one useful offline workspace',
    () async {
      final harness = await TasksExampleTestHarness.open(autoSync: false);
      final entityGraph = harness.entityGraph;
      addTearDown(harness.close);

      await seedTasksDemo(entityGraph);
      await seedTasksDemo(entityGraph);

      expect(entityGraph.taskProjects.all, hasLength(2));
      final tasks = await TaskList.all(
        entityGraph,
        archives: ArchiveVisibility.include,
      ).useAll((items) => List<Task>.of(items));
      expect(tasks, hasLength(4));
      expect(
        tasks.map((task) => task.title),
        containsAll([
          'Define the domain once',
          'Inspect generated infrastructure',
          'Submit the hackathon demo',
          'Explore custom sync connectors',
        ]),
      );
      expect(
        tasks
            .singleWhere(
              (task) => task.title == 'Inspect generated infrastructure',
            )
            .status,
        TaskStatus.inProgress,
      );
      expect(
        tasks
            .singleWhere((task) => task.title == 'Submit the hackathon demo')
            .status,
        TaskStatus.done,
      );
      expect(
        tasks
            .singleWhere(
              (task) => task.title == 'Explore custom sync connectors',
            )
            .isArchived,
        isTrue,
      );
      expect(entityGraph.syncQueue.items, isNotEmpty);

      final activity = await TaskActivityList.all(
        entityGraph,
      ).useAll((items) => List<TaskActivity>.of(items));
      expect(activity, hasLength(greaterThan(tasks.length)));
    },
  );
}
