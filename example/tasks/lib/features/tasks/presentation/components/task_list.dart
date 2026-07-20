import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/features/app_shell/presentation/components/entity_action_feedback.dart';
import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';

final class TaskListPane extends HookWidget {
  const TaskListPane({
    required this.entityGraph,
    required this.filter,
    super.key,
  });

  final TasksExampleEntityGraph entityGraph;
  final TaskListFilter filter;

  @override
  Widget build(BuildContext context) {
    final (filterPredicate, archives) = switch (filter) {
      TaskListFilter.open => (
        TaskFields.status.equals(TaskStatus.todo) |
            TaskFields.status.equals(TaskStatus.inProgress),
        ArchiveVisibility.exclude,
      ),
      TaskListFilter.completed => (
        TaskFields.status.equals(TaskStatus.done),
        ArchiveVisibility.exclude,
      ),
      TaskListFilter.archived => (
        EntityPredicate<Task>.all(),
        ArchiveVisibility.only,
      ),
    };
    final tasks = useObservedEntityList(
      () =>
          TaskList.all(entityGraph, where: filterPredicate, archives: archives),
      keys: [entityGraph, filter],
    );
    final scrollController = useEntityQueryScrollController(tasks.query);

    return Column(
      children: [
        _TaskFilters(selected: filter),
        const Divider(height: 1),
        Expanded(
          child: tasks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            empty: () => _EmptyTasks(filter: filter),
            failure: (error, retry) =>
                _QueryFailure(error: error, retry: retry),
            data:
                (
                  items, {
                  required hasMore,
                  required refreshing,
                  refreshError,
                }) => Column(
                  children: [
                    if (refreshing)
                      const LinearProgressIndicator(
                        key: Key('tasksQueryProgress'),
                      ),
                    if (refreshError != null)
                      MaterialBanner(
                        content: Text('Refresh failed: $refreshError'),
                        actions: [
                          TextButton(
                            onPressed: tasks.refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        key: const Key('tasksList'),
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: items.length + (hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _TaskTile(
                            entityGraph: entityGraph,
                            task: items[index],
                            filter: filter,
                          );
                        },
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ],
    );
  }
}

final class _TaskTile extends HookWidget {
  const _TaskTile({
    required this.entityGraph,
    required this.task,
    required this.filter,
  });

  final TasksExampleEntityGraph entityGraph;
  final Task task;
  final TaskListFilter filter;

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
        return ListTile(
          key: ValueKey('task:${task.id.value}'),
          onTap: () => TaskDetailsRoute(task.id, filter: filter).go(context),
          leading: Checkbox(
            key: ValueKey('completeTask:${task.id.value}'),
            value: task.isCompleted,
            onChanged: (_) => action.run(
              () => task.isCompleted ? task.reopen() : task.complete(),
            ),
          ),
          title: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: task.isCompleted
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          subtitle: Text(
            [
              task.status.name,
              task.priority.name,
              if (project != null) project.title,
              if (task.dueAt != null) 'due ${_dateLabel(task.dueAt!)}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<_TaskMenuAction>(
            key: ValueKey('taskMenu:${task.id.value}'),
            tooltip: 'Task actions',
            onSelected: (menuAction) => switch (menuAction) {
              _TaskMenuAction.start => action.run(task.start),
              _TaskMenuAction.complete => action.run(task.complete),
              _TaskMenuAction.reopen => action.run(task.reopen),
              _TaskMenuAction.archive => action.run(task.archive),
              _TaskMenuAction.unarchive => action.run(task.unarchive),
            },
            itemBuilder: (_) => [
              if (task.status == TaskStatus.todo)
                const PopupMenuItem(
                  value: _TaskMenuAction.start,
                  child: Text('Start'),
                ),
              if (!task.isCompleted)
                const PopupMenuItem(
                  value: _TaskMenuAction.complete,
                  child: Text('Complete'),
                ),
              if (task.isCompleted)
                const PopupMenuItem(
                  value: _TaskMenuAction.reopen,
                  child: Text('Reopen'),
                ),
              if (task.isArchived)
                const PopupMenuItem(
                  value: _TaskMenuAction.unarchive,
                  child: Text('Unarchive'),
                )
              else
                const PopupMenuItem(
                  value: _TaskMenuAction.archive,
                  child: Text('Archive'),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _TaskMenuAction { start, complete, reopen, archive, unarchive }

final class _TaskFilters extends StatelessWidget {
  const _TaskFilters({required this.selected});

  final TaskListFilter selected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final filter in TaskListFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('filter:${filter.name}'),
                label: Text(switch (filter) {
                  TaskListFilter.open => 'Open',
                  TaskListFilter.completed => 'Completed',
                  TaskListFilter.archived => 'Archived',
                }),
                selected: selected == filter,
                onSelected: (_) => TasksRoute(filter: filter).go(context),
              ),
            ),
        ],
      ),
    );
  }
}

final class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.filter});

  final TaskListFilter filter;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(switch (filter) {
        TaskListFilter.open => 'No open tasks. Add one when you are ready.',
        TaskListFilter.completed => 'No completed tasks yet.',
        TaskListFilter.archived => 'No archived tasks.',
      }, textAlign: TextAlign.center),
    ),
  );
}

final class _QueryFailure extends StatelessWidget {
  const _QueryFailure({required this.error, required this.retry});

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: FilledButton(
        onPressed: retry,
        child: Text('Retry loading tasks: $error'),
      ),
    ),
  );
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
