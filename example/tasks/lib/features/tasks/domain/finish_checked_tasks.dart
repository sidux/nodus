import 'package:nodus/nodus.dart';

import 'task.dart';
import 'task_step.dart';

/// Finishes an open task once every step of its checklist is checked off.
@EntityProcess(
  name: 'finishCheckedTasks',
  source: WorkSource(Task, fields: [#status]),
  wakeOn: [
    WorkSource(TaskStep, fields: [#done, #deletedAt]),
  ],
)
abstract final class FinishCheckedTasksProcessDeclaration {}
