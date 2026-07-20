import 'package:flutter/widgets.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';
import 'package:tasks_example/features/tasks/presentation/components/task_editor.dart';
import 'package:tasks_example/nodus.g.dart';

Widget editTaskPage(
  TasksExampleEntityGraph entityGraph,
  LocalId<Task> taskId, {
  TaskListFilter filter = TaskListFilter.open,
  Key? key,
}) => TaskEditor(
  entityGraph: entityGraph,
  taskId: taskId,
  returnFilter: filter,
  key: key,
);
