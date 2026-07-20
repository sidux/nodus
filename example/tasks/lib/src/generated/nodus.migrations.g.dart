// GENERATED FILE. DO NOT EDIT.
// Exceptional transitions are configured with NodusMigrationHooks.

import 'package:nodus/nodus_migrations.dart';

MigrationStrategy nodusMigrationStrategy<D extends GeneratedDatabase>({
  required Iterable<SyncTargetId> initialPullTargets,
  NodusMigrationHooks<D>? hooks,
}) {
  final _ = hooks;
  final cursorTargets = initialPullTargets.toSet();
  Future<void> generatedUpgrade(Migrator migrator, int from, int to) async =>
      throw StateError('No generated Drift migration for $from -> $to.');

  return MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      for (final target in cursorTargets) {
        await migrator.database.customStatement(
          'insert or ignore into local_entity_sync_cursor '
          '(sync_target, cursor) values (?, 0)',
          [target.wireName],
        );
      }
    },
    onUpgrade: generatedUpgrade,
  );
}
