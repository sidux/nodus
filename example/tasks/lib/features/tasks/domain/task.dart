import 'package:nodus/nodus.dart';

import '../../accounts/domain/account.dart';
import 'task_project.dart';

enum TaskStatus { todo, inProgress, done }

enum TaskPriority { low, normal, high }

@Entity(
  orderScope: [#projectId],
  indexes: [
    CompoundIndex.query([#archivedAt, #deletedAt, #status, #dueAt]),
    CompoundIndex.query([#projectId, #archivedAt, #deletedAt]),
  ],
)
abstract class Task
    implements
        OwnedBy<Task, Account>,
        SoftDeletable,
        Archivable,
        Ordered,
        ActivityTracked,
        Collaborative<Account> {
  @Reference(onDelete: ReferenceDeleteAction.setNull)
  abstract final LocalId<TaskProject>? projectId;

  @Persisted(minLength: 1, maxLength: 160, conflict: ConflictStrategy.localWins)
  abstract final String title;

  @Persisted(maxLength: 1000, conflict: ConflictStrategy.localWins)
  abstract final String? description;

  @Persisted(
    defaultValue: TaskStatus.todo,
    transitions: [
      AllowedTransition(TaskStatus.todo, TaskStatus.inProgress),
      AllowedTransition(TaskStatus.todo, TaskStatus.done),
      AllowedTransition(TaskStatus.inProgress, TaskStatus.todo),
      AllowedTransition(TaskStatus.inProgress, TaskStatus.done),
      AllowedTransition(TaskStatus.done, TaskStatus.todo),
    ],
  )
  abstract final TaskStatus status;

  @Persisted(defaultValue: TaskPriority.normal)
  abstract final TaskPriority priority;

  abstract final DateTime? dueAt;
  abstract final DateTime? completedAt;

  abstract final DateTime createdAt;

  bool get isArchived => archivedAt != null;
  bool get isCompleted => status == TaskStatus.done;

  @override
  String get activityLabel => title;

  @Action()
  Future<void> edit({
    required String title,
    required String? description,
    required TaskPriority priority,
    required DateTime? dueAt,
  });

  @Action()
  Future<void> moveToProject({required LocalId<TaskProject>? projectId});

  @Action(
    values: [
      ActionValue(#status, TaskStatus.inProgress),
      ActionValue.clear(#completedAt),
    ],
  )
  Future<void> start();

  @Action(
    values: [
      ActionValue(#status, TaskStatus.done),
      ActionValue.clockNow(#completedAt),
    ],
  )
  Future<void> complete();

  @Action(
    values: [
      ActionValue(#status, TaskStatus.todo),
      ActionValue.clear(#completedAt),
    ],
  )
  Future<void> reopen();
}
