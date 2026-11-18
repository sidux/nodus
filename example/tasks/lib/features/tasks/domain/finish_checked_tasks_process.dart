import 'package:tasks_example/nodus.g.dart';

/// Installs the process that finishes an open task once every step of its
/// checklist is checked off.
void installFinishCheckedTasks(TasksExampleEntityGraph entityGraph) {
  entityGraph.installFinishCheckedTasksProcess(
    scope: () =>
        TaskFields.status.isIn({TaskStatus.todo, TaskStatus.inProgress}),
    run: (task, _) async {
      final checked = await task
          .steps(entityGraph)
          .useAll(
            (steps) => steps.isNotEmpty && steps.every((step) => step.done),
          );
      if (checked) await task.complete();
    },
  );
}
