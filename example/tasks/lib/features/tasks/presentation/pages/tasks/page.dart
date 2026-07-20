import 'package:flutter/widgets.dart';

import 'package:tasks_example/nodus.g.dart';
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';
import 'package:tasks_example/features/tasks/presentation/components/tasks_view.dart';

Widget tasksPage(
  TasksExampleEntityGraph entityGraph, {
  TaskListFilter filter = TaskListFilter.open,
  Key? key,
}) => TasksView(entityGraph: entityGraph, filter: filter, key: key);
