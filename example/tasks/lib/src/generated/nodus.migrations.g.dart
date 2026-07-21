// GENERATED FILE. DO NOT EDIT.
// Exceptional transitions are configured with NodusMigrationHooks.

import 'package:nodus/nodus_migrations.dart';

import './nodus.runtime.g.steps.dart' as steps;

MigrationStrategy nodusMigrationStrategy<D extends GeneratedDatabase>({
  required Iterable<SyncTargetId> initialPullTargets,
  NodusMigrationHooks<D>? hooks,
}) {
  final configuredHooks = hooks ?? NodusMigrationHooks<D>();
  final cursorTargets = initialPullTargets.toSet();
  final stepUpgrade = steps.stepByStep(
    from1To2: (migrator, schema) async {
      final transition = NodusSchemaTransition(from: 1, to: 2);
      final plan = configuredHooks.plan(transition);
      if (plan.runsGeneratedSteps) {}
      await applyNodusMigrationPlan<D>(
        plan: plan,
        migrator: migrator,
        transition: transition,
      );
      final violations = await migrator.database
          .customSelect('pragma foreign_key_check')
          .get();
      if (violations.isNotEmpty) {
        throw StateError('Drift migration introduced foreign-key violations.');
      }
    },
    from2To3: (migrator, schema) async {
      final transition = NodusSchemaTransition(from: 2, to: 3);
      final plan = configuredHooks.plan(transition);
      if (plan.runsGeneratedSteps) {}
      await applyNodusMigrationPlan<D>(
        plan: plan,
        migrator: migrator,
        transition: transition,
      );
      final violations = await migrator.database
          .customSelect('pragma foreign_key_check')
          .get();
      if (violations.isNotEmpty) {
        throw StateError('Drift migration introduced foreign-key violations.');
      }
    },
    from3To4: (migrator, schema) async {
      final transition = NodusSchemaTransition(from: 3, to: 4);
      final plan = configuredHooks.plan(transition);
      if (plan.runsGeneratedSteps) {}
      await applyNodusMigrationPlan<D>(
        plan: plan,
        migrator: migrator,
        transition: transition,
      );
      final violations = await migrator.database
          .customSelect('pragma foreign_key_check')
          .get();
      if (violations.isNotEmpty) {
        throw StateError('Drift migration introduced foreign-key violations.');
      }
    },
  );
  Future<void> generatedUpgrade(Migrator migrator, int from, int to) =>
      stepUpgrade(migrator, from, to);

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
