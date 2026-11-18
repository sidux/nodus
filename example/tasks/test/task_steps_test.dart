import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_example/features/tasks/domain/finish_checked_tasks_process.dart';
import 'package:tasks_example/nodus.g.dart';

import 'nodus_test_harness.g.dart';

void main() {
  final accountId = LocalId<Account>('00000000-0000-0000-0000-000000000001');

  /// A synchronized task, retained like a visible row keeps it, whose steps
  /// nothing keeps loaded.
  Future<(TasksExampleEntityGraph, Task)> openTask() async {
    final graph = (await TasksExampleTestHarness.open(
      accountId: accountId,
      autoSync: false,
    )).entityGraph;
    addTearDown(graph.close);
    final created = await graph.tasks.create(title: 'Write the report');
    final lease = (await graph.tasks.loadById(created.id))!;
    addTearDown(lease.release);
    await graph.sync();
    return (graph, lease.value);
  }

  Future<List<(String, bool)>> stepsOf(
    TasksExampleEntityGraph graph,
    Task task,
  ) => task
      .steps(graph)
      .useAll((steps) => [for (final step in steps) (step.title, step.done)]);

  test('Given a checked step removed and synchronized, When the step is added '
      'again, Then it comes back unchecked', () async {
    final (graph, task) = await openTask();
    await task.addStep(graph, 'Outline');
    await task.checkStep(graph, 'Outline');
    await graph.sync();
    await task.steps(graph).useAll((steps) => steps.single.remove());
    // Synchronizing releases the pending-work pin, so nothing else keeps the
    // removed step loaded.
    await graph.sync();

    await task.addStep(graph, 'Outline');

    expect(await stepsOf(graph, task), [('Outline', false)]);
  });

  test('Given a task with two steps, When the last one is checked off, Then '
      'the task is finished once local work settles', () async {
    final (graph, task) = await openTask();
    installFinishCheckedTasks(graph);
    await task.addStep(graph, 'Outline');
    await task.addStep(graph, 'Draft');
    await task.checkStep(graph, 'Outline');
    await graph.settleLocal();
    expect(task.isCompleted, isFalse);

    await task.checkStep(graph, 'Draft');
    await graph.settleLocal();

    expect(task.isCompleted, isTrue);
  });

  test('Given a process still running, When local work settles, Then it '
      'waits for the run and the changes it makes', () async {
    final (graph, task) = await openTask();
    final release = Completer<void>();
    graph.installFinishCheckedTasksProcess(
      run: (source, _) async {
        await release.future;
        await source.complete();
      },
    );
    var settled = false;
    final settling = graph.settleLocal().then((_) => settled = true);
    await graph.flushLocal();
    await pumpEventQueue();
    expect(settled, isFalse);

    release.complete();
    await settling;

    expect(task.isCompleted, isTrue);
  });
}
