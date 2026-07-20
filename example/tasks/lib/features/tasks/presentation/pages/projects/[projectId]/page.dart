import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/features/app_shell/presentation/components/entity_action_feedback.dart';
import 'package:tasks_example/nodus.g.dart';

final class TaskProjectDetailsPage extends StatelessWidget {
  const TaskProjectDetailsPage(this.entityGraph, this.projectId, {super.key});

  final TasksExampleEntityGraph entityGraph;
  final LocalId<TaskProject> projectId;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final project = entityGraph.taskProjects.byId(projectId);
        if (project == null || project.deletedAt != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project')),
            body: const Center(child: Text('Project not found')),
          );
        }
        return _LoadedProjectDetails(
          entityGraph: entityGraph,
          project: project,
        );
      },
    );
  }
}

final class _LoadedProjectDetails extends HookWidget {
  const _LoadedProjectDetails({
    required this.entityGraph,
    required this.project,
  });

  final TasksExampleEntityGraph entityGraph;
  final TaskProject project;

  @override
  Widget build(BuildContext context) {
    final tasks = useObservedEntityList(
      () => project.tasks(entityGraph, pageSize: 50),
      keys: [entityGraph, project.id],
    );
    final scrollController = useEntityQueryScrollController(tasks.query);
    final action = useEntityActionFeedback(
      context,
      failureMessage: 'Project action failed',
    );

    void reorder(int oldIndex, int newIndex) {
      action.run(() async {
        final destinationIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
        if (oldIndex == destinationIndex) return;
        final current = tasks.state.items;
        final moved = current[oldIndex];
        final neighbor = current[destinationIndex];
        if (destinationIndex < oldIndex) {
          await entityGraph.tasks.moveBefore(moved.id, neighbor.id);
        } else {
          await entityGraph.tasks.moveAfter(moved.id, neighbor.id);
        }
      });
    }

    Future<void> removeProject() async {
      await project.remove();
      if (!context.mounted) return;
      const TaskProjectsRoute().go(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: Observer(builder: (_) => Text(project.title)),
        actions: [
          IconButton(
            key: const Key('deleteTaskProjectButton'),
            tooltip: 'Delete project',
            onPressed: action.isRunning
                ? null
                : () => action.run(removeProject),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        empty: () => const Center(child: Text('No tasks in this project')),
        failure: (error, retry) => Center(
          child: FilledButton(
            onPressed: retry,
            child: Text('Retry loading project tasks: $error'),
          ),
        ),
        data: (items, {required hasMore, required refreshing, refreshError}) =>
            Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Drag tasks to change their canonical offline-first order.',
                  ),
                ),
                if (hasMore)
                  const LinearProgressIndicator(key: Key('projectTasksPaging')),
                Expanded(
                  child: ReorderableListView.builder(
                    key: const Key('projectTasksList'),
                    scrollController: scrollController,
                    itemCount: items.length,
                    onReorderItem: reorder,
                    itemBuilder: (context, index) {
                      final task = items[index];
                      return Observer(
                        key: ValueKey('projectTask:${task.id.value}'),
                        builder: (_) => ListTile(
                          leading: Icon(
                            task.isCompleted
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(task.title),
                          subtitle: Text(
                            '${task.status.name} · ${task.priority.name} priority',
                          ),
                          onTap: () => TaskDetailsRoute(task.id).go(context),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
