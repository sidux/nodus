import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tasks_example/nodus.g.dart';

final class NewTaskProjectPage extends HookWidget {
  const NewTaskProjectPage(this.entityGraph, {super.key});

  final TasksExampleEntityGraph entityGraph;

  @override
  Widget build(BuildContext context) {
    final title = useTextEditingController();
    final action = useEntityAction();

    Future<void> save() => action.run(() async {
      final project = await entityGraph.taskProjects.create(title: title.text);
      if (!context.mounted) return;
      TaskProjectDetailsRoute(project.id).go(context);
    });

    final errorText = switch (action.error) {
      EntityValidationException(:final message) => message,
      final Object error => 'Could not save: $error',
      null => null,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('New project')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('taskProjectTitleField'),
                  controller: title,
                  autofocus: true,
                  maxLength: TaskProjectFields.title.constraints.maxLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => save(),
                  decoration: InputDecoration(
                    labelText: 'Project name',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('saveTaskProjectButton'),
                  onPressed: action.isRunning ? null : save,
                  child: Text(
                    action.isRunning ? 'Creating…' : 'Create project',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
