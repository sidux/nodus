import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/features/app_shell/presentation/components/adaptive_shell.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';
import 'package:tasks_example/nodus.g.dart';
import 'task_details.dart';
import 'task_list.dart';

final class TasksView extends StatelessWidget {
  const TasksView({
    required this.entityGraph,
    required this.filter,
    this.selectedTaskId,
    super.key,
  });

  final TasksExampleEntityGraph entityGraph;
  final TaskListFilter filter;
  final LocalId<Task>? selectedTaskId;

  @override
  Widget build(BuildContext context) {
    final isExpanded =
        MediaQuery.sizeOf(context).width >= AdaptiveShell.expandedBreakpoint;
    final selectedId = selectedTaskId;
    if (!isExpanded && selectedId != null) {
      return TaskDetailScaffold(
        entityGraph: entityGraph,
        taskId: selectedId,
        filter: filter,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [_SyncQueueAction(entityGraph: entityGraph)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newTaskButton'),
        onPressed: () => NewTaskRoute(filter: filter).go(context),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      body: isExpanded
          ? Row(
              children: [
                SizedBox(
                  width: 380,
                  child: TaskListPane(entityGraph: entityGraph, filter: filter),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedId == null
                      ? const Center(child: Text('Select a task to inspect it'))
                      : TaskDetailsPane(
                          entityGraph: entityGraph,
                          taskId: selectedId,
                          filter: filter,
                        ),
                ),
              ],
            )
          : TaskListPane(entityGraph: entityGraph, filter: filter),
    );
  }
}

final class _SyncQueueAction extends StatelessWidget {
  const _SyncQueueAction({required this.entityGraph});

  final TasksExampleEntityGraph entityGraph;

  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) {
      final pending = entityGraph.syncQueue.items.length;
      return Badge(
        key: const Key('syncQueueBadge'),
        isLabelVisible: pending > 0,
        label: Text(pending > 99 ? '99+' : '$pending'),
        child: IconButton(
          key: const Key('openSyncCenterButton'),
          tooltip: pending == 0
              ? 'Open sync center'
              : 'Open sync center: $pending durable item(s)',
          onPressed: () => const SyncCenterRoute().go(context),
          icon: const Icon(Icons.sync),
        ),
      );
    },
  );
}
