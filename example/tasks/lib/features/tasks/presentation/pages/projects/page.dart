import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/nodus.g.dart';

final class TaskProjectsPage extends HookWidget {
  const TaskProjectsPage(this.entityGraph, {super.key});

  final TasksExampleEntityGraph entityGraph;

  @override
  Widget build(BuildContext context) {
    final projects = useObservedEntityList(
      () => TaskProjectList.all(entityGraph),
      keys: [entityGraph],
      loadAllPages: true,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newTaskProjectButton'),
        onPressed: () => const NewTaskProjectRoute().go(context),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New project'),
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        empty: () => const Center(child: Text('No projects yet')),
        failure: (error, retry) => Center(
          child: FilledButton(
            onPressed: retry,
            child: Text('Retry loading projects: $error'),
          ),
        ),
        data: (items, {required hasMore, required refreshing, refreshError}) =>
            hasMore
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                key: const Key('taskProjectsList'),
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final project = items[index];
                  return Observer(
                    key: ValueKey('project:${project.id.value}'),
                    builder: (_) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(project.title),
                      onTap: () =>
                          TaskProjectDetailsRoute(project.id).go(context),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
