import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';

final class TaskEditor extends StatelessWidget {
  const TaskEditor({
    required this.entityGraph,
    this.taskId,
    this.returnFilter = TaskListFilter.open,
    super.key,
  });

  final TasksExampleEntityGraph entityGraph;
  final LocalId<Task>? taskId;
  final TaskListFilter returnFilter;

  @override
  Widget build(BuildContext context) {
    final id = taskId;
    return id == null
        ? _TaskEditorForm(
            entityGraph: entityGraph,
            task: null,
            returnFilter: returnFilter,
          )
        : _ExistingTaskEditor(
            entityGraph: entityGraph,
            taskId: id,
            returnFilter: returnFilter,
          );
  }
}

final class _ExistingTaskEditor extends HookWidget {
  const _ExistingTaskEditor({
    required this.entityGraph,
    required this.taskId,
    required this.returnFilter,
  });

  final TasksExampleEntityGraph entityGraph;
  final LocalId<Task> taskId;
  final TaskListFilter returnFilter;

  @override
  Widget build(BuildContext context) {
    final lookup = useObservedEntityLookup(
      () => entityGraph.tasks.lookup(taskId),
      keys: [entityGraph, taskId],
    );
    return lookup.when(
      loading: _EditorLoading.new,
      empty: _MissingEditorTask.new,
      failure: (error, retry) => _EditorFailure(error: error, retry: retry),
      data: (task, {required refreshing, refreshError}) => _TaskEditorForm(
        entityGraph: entityGraph,
        task: task,
        returnFilter: returnFilter,
      ),
    );
  }
}

final class _TaskEditorForm extends HookWidget {
  const _TaskEditorForm({
    required this.entityGraph,
    required this.task,
    required this.returnFilter,
  });

  final TasksExampleEntityGraph entityGraph;
  final Task? task;
  final TaskListFilter returnFilter;

  @override
  Widget build(BuildContext context) {
    final existing = task;
    final draft = useEntityMutationDraft(
      () => existing == null
          ? entityGraph.tasks.beginCreate()
          : existing.beginEdit(),
      keys: [entityGraph, existing],
    );
    final title = useEntityDraftTextField(draft.titleField);
    final description = useEntityDraftNullableTextField(draft.descriptionField);
    final titleFocus = useFocusNode();
    final saveAction = useEntityAction();
    final projectId = useEntityDraftValue(draft.projectIdField);
    final priority = useEntityDraftValue(draft.priorityField);
    final dueAt = useEntityDraftValue(draft.dueAtField);
    final selectedProjectId = projectId.value;
    final projects = useObservedEntityList(
      () => TaskProjectList.all(
        entityGraph,
        where: selectedProjectId == null
            ? TaskProjectFields.deletedAt.isNull
            : TaskProjectFields.deletedAt.isNull |
                  TaskProjectFields.id.equals(selectedProjectId),
        orderBy: TaskProjectFields.title.ascending(),
      ),
      keys: [entityGraph, selectedProjectId],
      loadAllPages: true,
    );

    Future<void> chooseDueDate() async {
      final today = DateTime.now();
      final selected = await showDatePicker(
        context: context,
        initialDate: dueAt.value?.toLocal() ?? today,
        firstDate: DateTime(today.year - 1),
        lastDate: DateTime(today.year + 10),
      );
      if (selected != null) dueAt.set(selected.toUtc());
    }

    Future<void> save() => saveAction.run(() async {
      final saved = await draft.save();
      if (!context.mounted) return;
      TaskDetailsRoute(saved.id, filter: returnFilter).go(context);
    });

    final errorText = switch (saveAction.error) {
      EntityValidationException(:final message) => message,
      final Object error => 'Could not save task: $error',
      null => null,
    };

    return Scaffold(
      appBar: AppBar(title: Text(existing == null ? 'New task' : 'Edit task')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('taskTitleField'),
                  controller: title,
                  focusNode: titleFocus,
                  autofocus: existing == null,
                  maxLength: TaskFields.title.constraints.maxLength,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('taskDescriptionField'),
                  controller: description,
                  maxLength: TaskFields.description.constraints.maxLength,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TaskPriority>(
                  key: const Key('taskPriorityField'),
                  initialValue: priority.value,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: [
                    for (final value in TaskPriority.values)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) priority.set(value);
                  },
                ),
                const SizedBox(height: 12),
                projects.when(
                  loading: () => const LinearProgressIndicator(),
                  empty: () => DropdownButtonFormField<LocalId<TaskProject>?>(
                    key: const Key('taskProjectField'),
                    initialValue: projectId.value,
                    decoration: const InputDecoration(labelText: 'Project'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Inbox')),
                    ],
                    onChanged: projectId.set,
                  ),
                  failure: (error, retry) =>
                      Text('Could not load projects: $error'),
                  data:
                      (
                        items, {
                        required hasMore,
                        required refreshing,
                        refreshError,
                      }) => hasMore
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<LocalId<TaskProject>?>(
                          key: const Key('taskProjectField'),
                          initialValue: projectId.value,
                          decoration: const InputDecoration(
                            labelText: 'Project',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Inbox'),
                            ),
                            for (final project in items)
                              DropdownMenuItem(
                                value: project.id,
                                child: Text(project.title),
                              ),
                          ],
                          onChanged: projectId.set,
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('taskDueDateButton'),
                        onPressed: chooseDueDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          dueAt.value == null
                              ? 'No due date'
                              : _dateLabel(dueAt.value!),
                        ),
                      ),
                    ),
                    if (dueAt.value != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('clearTaskDueDateButton'),
                        tooltip: 'Clear due date',
                        onPressed: () => dueAt.set(null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('saveTaskButton'),
                  onPressed: saveAction.isRunning ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(saveAction.isRunning ? 'Saving…' : 'Save task'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _EditorLoading extends StatelessWidget {
  const _EditorLoading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

final class _EditorFailure extends StatelessWidget {
  const _EditorFailure({required this.error, required this.retry});

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit task')),
    body: Center(
      child: FilledButton(onPressed: retry, child: Text('Retry: $error')),
    ),
  );
}

final class _MissingEditorTask extends StatelessWidget {
  const _MissingEditorTask();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit task')),
    body: Center(
      child: FilledButton(
        onPressed: () => const TasksRoute().go(context),
        child: const Text('Task not found'),
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
