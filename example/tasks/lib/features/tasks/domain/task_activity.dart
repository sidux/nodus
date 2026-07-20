import 'package:nodus/nodus.dart';

import '../../accounts/domain/account.dart';
import 'task.dart';

@Entity()
abstract class TaskActivity
    implements OwnedBy<TaskActivity, Account>, ActivityOf<Task, Account> {
  String get description {
    final verb = switch (operation) {
      ActivityOperation.created => 'Created',
      ActivityOperation.edited => 'Updated',
      ActivityOperation.removed => 'Deleted',
      ActivityOperation.restored => 'Restored',
      ActivityOperation.archived => 'Archived',
      ActivityOperation.unarchived => 'Unarchived',
      ActivityOperation.activated => 'Activated',
      ActivityOperation.deactivated => 'Deactivated',
      ActivityOperation.collaborationChanged => 'Changed access for',
      ActivityOperation.reordered => 'Reordered',
      ActivityOperation.moved => 'Moved',
      _ => switch (operation.actionName) {
        'edit' => 'Updated',
        'start' => 'Started',
        'complete' => 'Completed',
        'reopen' => 'Reopened',
        final action? => action,
        null => 'Changed',
      },
    };
    return '$verb “$label”';
  }
}
