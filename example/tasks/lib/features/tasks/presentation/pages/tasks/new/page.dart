import 'package:flutter/widgets.dart';

import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';
import 'package:tasks_example/features/tasks/presentation/components/task_editor.dart';

Widget newTaskPage(
  TasksExampleEntityGraph entityGraph, {
  TaskListFilter filter = TaskListFilter.open,
  Key? key,
}) => TaskEditor(entityGraph: entityGraph, returnFilter: filter, key: key);
