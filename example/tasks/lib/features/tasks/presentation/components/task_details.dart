import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/features/app_shell/presentation/components/entity_action_feedback.dart';
import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';

final class TaskDetailScaffold extends StatelessWidget {
  const TaskDetailScaffold({
    required this.entityGraph,
    required this.taskId,
    required this.filter,
    super.key,
  });

  final TasksExampleEntityGraph entityGraph;
  final LocalId<Task> taskId;
  final TaskListFilter filter;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(
        onPressed: () => TasksRoute(filter: filter).go(context),
      ),
      title: const Text('Task'),
    ),
    body: TaskDetailsPane(
      entityGraph: entityGraph,
      taskId: taskId,
      filter: filter,
    ),
  );
}

final class TaskDetailsPane extends HookWidget {
  const TaskDetailsPane({
    required this.entityGraph,
    required this.taskId,
    required this.filter,
    super.key,
  });

  final TasksExampleEntityGraph entityGraph;
  final LocalId<Task> taskId;
  final TaskListFilter filter;

  @override
  Widget build(BuildContext context) {
    final lookup = useObservedEntityLookup(
      () => entityGraph.tasks.lookup(taskId),
      keys: [entityGraph, taskId],
    );
    final activity = useObservedEntityList(
      () => TaskActivityList.forTask(entityGraph, taskId, pageSize: 5),
      keys: [entityGraph, taskId],
    );

    return lookup.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      empty: () => _MissingTask(taskId: taskId, filter: filter),
      failure: (error, retry) => _DetailFailure(error: error, retry: retry),
      data: (task, {required refreshing, refreshError}) => _LoadedTaskDetails(
        entityGraph: entityGraph,
        task: task,
        filter: filter,
        activity: activity,
      ),
    );
  }
}

final class _LoadedTaskDetails extends HookWidget {
  const _LoadedTaskDetails({
    required this.entityGraph,
    required this.task,
    required this.filter,
    required this.activity,
  });

  final TasksExampleEntityGraph entityGraph;
  final Task task;
  final TaskListFilter filter;
  final ObservedEntityQuery<TaskActivity> activity;

  @override
  Widget build(BuildContext context) {
    final action = useEntityActionFeedback(
      context,
      failureMessage: 'Task action failed',
    );
    return Observer(
      builder: (_) {
        final projectId = task.projectId;
        final project = projectId == null
            ? null
            : entityGraph.taskProjects.byId(projectId);
        return ListView(
          key: const Key('taskDetails'),
          padding: const EdgeInsets.all(24),
          children: [
            Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
            if (task.description case final description?) ...[
              const SizedBox(height: 12),
              Text(description),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  key: const Key('taskStatusChip'),
                  avatar: Icon(_statusIcon(task.status), size: 18),
                  label: Text(task.status.name),
                ),
                Chip(
                  key: const Key('taskPriorityChip'),
                  label: Text('${task.priority.name} priority'),
                ),
                Chip(label: Text(project?.title ?? 'Inbox')),
                if (task.dueAt != null)
                  Chip(label: Text('Due ${_dateLabel(task.dueAt!)}')),
                if (task.isArchived)
                  const Chip(
                    key: Key('taskArchivedChip'),
                    label: Text('Archived'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Server version ${task.serverVersion.value} · local changes are durable before sync',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('editTaskButton'),
                  onPressed: () =>
                      EditTaskRoute(task.id, filter: filter).go(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  key: const Key('manageTaskAccessButton'),
                  onPressed: () =>
                      TaskAccessRoute(task.id, filter: filter).go(context),
                  icon: const Icon(Icons.group_outlined),
                  label: const Text('Collaborate'),
                ),
                if (task.status == TaskStatus.todo)
                  OutlinedButton.icon(
                    key: const Key('startTaskButton'),
                    onPressed: () => action.run(task.start),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                if (!task.isCompleted)
                  OutlinedButton.icon(
                    key: const Key('completeSelectedTaskButton'),
                    onPressed: () => action.run(task.complete),
                    icon: const Icon(Icons.check),
                    label: const Text('Complete'),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('reopenSelectedTaskButton'),
                    onPressed: () => action.run(task.reopen),
                    icon: const Icon(Icons.undo),
                    label: const Text('Reopen'),
                  ),
                OutlinedButton.icon(
                  key: const Key('archiveSelectedTaskButton'),
                  onPressed: () => action.run(
                    () => task.isArchived ? task.unarchive() : task.archive(),
                  ),
                  icon: Icon(
                    task.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  label: Text(task.isArchived ? 'Unarchive' : 'Archive'),
                ),
                TextButton.icon(
                  key: const Key('deleteSelectedTaskButton'),
                  onPressed: action.isRunning
                      ? null
                      : () => action.run(() => _deleteTask(context)),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Recent activity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _TaskActivityPreview(activity: activity),
          ],
        );
      },
    );
  }

  Future<void> _deleteTask(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text(
          'The task becomes a synchronized tombstone and can still be restored by a repair flow.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDeleteTaskButton'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await task.remove();
    if (!context.mounted) return;
    TasksRoute(filter: filter).go(context);
  }
}

final class _TaskActivityPreview extends StatelessWidget {
  const _TaskActivityPreview({required this.activity});

  final ObservedEntityQuery<TaskActivity> activity;

  @override
  Widget build(BuildContext context) {
    return activity.when(
      loading: () => const LinearProgressIndicator(),
      empty: () => const Text('No recorded activity.'),
      failure: (error, retry) => Text('Could not load activity: $error'),
      data: (items, {required hasMore, required refreshing, refreshError}) =>
          Observer(
            builder: (_) => Column(
              children: [
                for (final event in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(event.description),
                    subtitle: Text(_dateLabel(event.occurredAt)),
                  ),
              ],
            ),
          ),
    );
  }
}

final class _DetailFailure extends StatelessWidget {
  const _DetailFailure({required this.error, required this.retry});

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton(
      onPressed: retry,
      child: Text('Retry loading task: $error'),
    ),
  );
}

final class _MissingTask extends StatelessWidget {
  const _MissingTask({required this.taskId, required this.filter});

  final LocalId<Task> taskId;
  final TaskListFilter filter;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.task_outlined, size: 48),
          const SizedBox(height: 16),
          const Text('Task not found'),
          const SizedBox(height: 8),
          Text(taskId.value, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => TasksRoute(filter: filter).go(context),
            child: const Text('Back to tasks'),
          ),
        ],
      ),
    ),
  );
}

IconData _statusIcon(TaskStatus status) => switch (status) {
  TaskStatus.todo => Icons.radio_button_unchecked,
  TaskStatus.inProgress => Icons.timelapse,
  TaskStatus.done => Icons.check_circle_outline,
};

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
