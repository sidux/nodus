import 'package:nodus/nodus.dart';

import '../../accounts/domain/account.dart';
import 'task.dart';

/// One checklist step of a task. Every device derives a step's identity from
/// its task and title, so adding the same step twice keeps one step, and
/// adding a removed step again brings it back.
@Entity(
  convergentCreates: true,
  identity: DerivedIdentity('6f1d2c3b-8a4e-4b7f-9c0d-2e5a7b9c1d3f', [
    #taskId,
    #title,
  ]),
  orderScope: [#taskId],
  indexes: [
    CompoundIndex([#taskId, #title], unique: true),
  ],
)
abstract class TaskStep
    implements OwnedBy<TaskStep, Account>, SoftDeletable, Ordered {
  @OwnerReference()
  @AccessReference()
  @Reference(inverse: 'steps', onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;

  @Persisted(editable: false, minLength: 1, maxLength: 160)
  abstract final String title;

  @Persisted(defaultValue: false, editable: false)
  abstract final bool done;

  @Action(values: [ActionValue(#done, true)])
  Future<void> check();

  @Action(values: [ActionValue(#done, false)])
  Future<void> uncheck();
}
