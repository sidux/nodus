import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/nodus.g.dart';

final class TaskActivityPage extends HookWidget {
  const TaskActivityPage(this.entityGraph, {super.key});

  final TasksExampleEntityGraph entityGraph;

  @override
  Widget build(BuildContext context) {
    final activity = useObservedEntityList(
      () => TaskActivityList.all(entityGraph, pageSize: 30),
      keys: [entityGraph],
    );
    final scrollController = useEntityQueryScrollController(activity.query);

    return Scaffold(
      appBar: AppBar(title: const Text('Task activity')),
      body: activity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        empty: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Task changes appear here automatically, including edits, completion, archiving, and collaboration.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        failure: (error, retry) => Center(
          child: FilledButton(
            onPressed: retry,
            child: Text('Retry loading activity: $error'),
          ),
        ),
        data: (items, {required hasMore, required refreshing, refreshError}) =>
            ListView.builder(
              key: const Key('taskActivityList'),
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final event = items[index];
                return Observer(
                  key: ValueKey('activity:${event.id.value}'),
                  builder: (_) => ListTile(
                    leading: CircleAvatar(child: Icon(_icon(event.operation))),
                    title: Text(event.description),
                    subtitle: Text(_dateTimeLabel(event.occurredAt)),
                  ),
                );
              },
            ),
      ),
    );
  }
}

IconData _icon(ActivityOperation operation) => switch (operation) {
  ActivityOperation.created => Icons.add_task,
  ActivityOperation.edited => Icons.edit_outlined,
  ActivityOperation.removed => Icons.delete_outline,
  ActivityOperation.restored => Icons.restore,
  ActivityOperation.archived => Icons.archive_outlined,
  ActivityOperation.unarchived => Icons.unarchive_outlined,
  ActivityOperation.collaborationChanged => Icons.group_outlined,
  ActivityOperation.reordered => Icons.reorder,
  ActivityOperation.moved => Icons.drive_file_move_outline,
  _ => switch (operation.actionName) {
    'start' => Icons.play_arrow,
    'complete' => Icons.check,
    'reopen' => Icons.undo,
    _ => Icons.history,
  },
};

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
