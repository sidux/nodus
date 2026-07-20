import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';

final class TaskAccessPage extends HookWidget {
  const TaskAccessPage(
    this.entityGraph,
    this.taskId, {
    this.filter = TaskListFilter.open,
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
    final controller = useTextEditingController();
    final grantsAccess = useState(true);
    final validationError = useState<String?>(null);
    final action = useEntityAction();

    return lookup.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      empty: () => Scaffold(
        appBar: AppBar(title: const Text('Collaborate')),
        body: const Center(child: Text('Task not found')),
      ),
      failure: (error, retry) => Scaffold(
        appBar: AppBar(title: const Text('Collaborate')),
        body: Center(
          child: FilledButton(onPressed: retry, child: Text('Retry: $error')),
        ),
      ),
      data: (task, {required refreshing, refreshError}) {
        Future<void> save() async {
          final collaboratorId = tryParseLocalId<Account>(
            controller.text.trim(),
          );
          if (collaboratorId == null) {
            validationError.value = 'Enter a valid collaborator account UUID.';
            return;
          }
          validationError.value = null;
          await action.run(() async {
            await task.setCollaborator(
              collaboratorId,
              active: grantsAccess.value,
            );
            if (!context.mounted) return;
            TaskDetailsRoute(task.id, filter: filter).go(context);
          });
        }

        final errorText = switch (action.error) {
          final Object error => 'Could not update access: $error',
          null => validationError.value,
        };
        return Observer(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Collaborate')),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Grant or revoke direct collaborator access. The generated semantic command remains ordered with offline task changes.',
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        key: const Key('collaboratorIdField'),
                        controller: controller,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Collaborator account UUID',
                          errorText: errorText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        key: const Key('collaboratorAccessSwitch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Access enabled'),
                        value: grantsAccess.value,
                        onChanged: action.isRunning
                            ? null
                            : (value) => grantsAccess.value = value,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('saveAccessButton'),
                        onPressed: action.isRunning ? null : save,
                        icon: const Icon(Icons.group_outlined),
                        label: Text(
                          action.isRunning
                              ? 'Saving…'
                              : grantsAccess.value
                              ? 'Grant access'
                              : 'Revoke access',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
