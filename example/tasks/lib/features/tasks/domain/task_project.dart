import 'package:nodus/nodus.dart';

import '../../accounts/domain/account.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [
    CompoundIndex.query([#deletedAt, #title]),
  ],
)
abstract class TaskProject
    implements OwnedBy<TaskProject, Account>, SoftDeletable, Ordered {
  @Persisted(minLength: 1, maxLength: 80, conflict: ConflictStrategy.localWins)
  abstract String title;

  void rename(String value) {
    title = value.trim();
  }
}
