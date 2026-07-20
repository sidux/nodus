part of '../nodus.dart';

/// One contiguous local database schema transition.
final class NodusSchemaTransition {
  factory NodusSchemaTransition({required int from, required int to}) {
    if (from <= 0) {
      throw RangeError.value(from, 'from', 'Schema versions start at one.');
    }
    if (to != from + 1) {
      throw ArgumentError.value(
        to,
        'to',
        'Schema transitions must be contiguous after version $from.',
      );
    }
    return NodusSchemaTransition._(from, to);
  }

  const NodusSchemaTransition._(this.from, this.to);

  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is NodusSchemaTransition && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from->$to';
}

final class NodusMigrationContext<D extends GeneratedDatabase> {
  const NodusMigrationContext({
    required this.migrator,
    required this.database,
    required this.transition,
  });

  final Migrator migrator;
  final D database;
  final NodusSchemaTransition transition;
}

/// Rebuilds the generated durable queue and cursor when a graph moves from a
/// single implicit transport to explicit per-target routing.
///
/// The application supplies only the one fact that generation cannot recover:
/// which target owned rows written by the previous schema. Drift derives the
/// complete destination table shapes, constraints, and indexes from the new
/// generated database.
Future<void> migrateImplicitSyncTarget({
  required Migrator migrator,
  required TableInfo<Table, Object?> workTable,
  required GeneratedColumn<String> workTargetColumn,
  required TableInfo<Table, Object?> cursorTable,
  required GeneratedColumn<String> cursorTargetColumn,
  required SyncTargetId legacyTarget,
}) async {
  final legacyTargetExpression = Constant<String>(legacyTarget.wireName);
  await migrator.alterTable(
    TableMigration(
      workTable,
      newColumns: [workTargetColumn],
      columnTransformer: {workTargetColumn: legacyTargetExpression},
    ),
  );
  await migrator.alterTable(
    TableMigration(
      cursorTable,
      newColumns: [cursorTargetColumn],
      columnTransformer: {cursorTargetColumn: legacyTargetExpression},
    ),
  );
  await migrator.database.customStatement(
    'drop index if exists local_entity_push_patch_idx',
  );
  await migrator.database.customStatement(
    'create index local_entity_push_patch_idx on local_entity_sync_work '
    "(sync_target, entity_type, entity_id, id) where direction = 'push' "
    "and kind = 'statePatch' and status = 'pending'",
  );
  await migrator.database.customStatement(
    'create index local_entity_sync_ready_idx on local_entity_sync_work '
    '(sync_target, status, next_attempt_at, direction, id)',
  );
}

typedef NodusManualMigration<D extends GeneratedDatabase> =
    Future<void> Function(NodusMigrationContext<D> context);

/// A type-safe decision for an exceptional generated schema transition.
sealed class NodusMigrationPlan<D extends GeneratedDatabase> {
  const NodusMigrationPlan._();

  const factory NodusMigrationPlan.generated() = _GeneratedMigrationPlan<D>;

  const factory NodusMigrationPlan.augment(NodusManualMigration<D> apply) =
      _AugmentedMigrationPlan<D>;

  const factory NodusMigrationPlan.replace(NodusManualMigration<D> apply) =
      _ReplacementMigrationPlan<D>;

  bool get runsGeneratedSteps;

  bool get handlesManualChanges;

  Future<void> apply(NodusMigrationContext<D> context);
}

final class _GeneratedMigrationPlan<D extends GeneratedDatabase>
    extends NodusMigrationPlan<D> {
  const _GeneratedMigrationPlan() : super._();

  @override
  bool get runsGeneratedSteps => true;

  @override
  bool get handlesManualChanges => false;

  @override
  Future<void> apply(NodusMigrationContext<D> context) async {}
}

sealed class _ManualMigrationPlan<D extends GeneratedDatabase>
    extends NodusMigrationPlan<D> {
  const _ManualMigrationPlan(this._apply) : super._();

  final NodusManualMigration<D> _apply;

  @override
  bool get handlesManualChanges => true;

  @override
  Future<void> apply(NodusMigrationContext<D> context) => _apply(context);
}

final class _AugmentedMigrationPlan<D extends GeneratedDatabase>
    extends _ManualMigrationPlan<D> {
  const _AugmentedMigrationPlan(super.apply);

  @override
  bool get runsGeneratedSteps => true;
}

final class _ReplacementMigrationPlan<D extends GeneratedDatabase>
    extends _ManualMigrationPlan<D> {
  const _ReplacementMigrationPlan(super.apply);

  @override
  bool get runsGeneratedSteps => false;
}

typedef NodusMigrationPlanner<D extends GeneratedDatabase> =
    NodusMigrationPlan<D> Function(NodusSchemaTransition transition);

/// Optional application policy for transitions that cannot be inferred.
///
/// With no override every safe transition uses generated steps. Applications
/// return an augmenting or replacement plan only for genuine data or semantic
/// decisions.
final class NodusMigrationHooks<D extends GeneratedDatabase> {
  const NodusMigrationHooks({NodusMigrationPlanner<D>? planner})
    : _planner = planner;

  final NodusMigrationPlanner<D>? _planner;

  NodusMigrationPlan<D> plan(NodusSchemaTransition transition) =>
      _planner?.call(transition) ?? NodusMigrationPlan<D>.generated();
}

Future<void> applyNodusMigrationPlan<D extends GeneratedDatabase>({
  required NodusMigrationPlan<D> plan,
  required Migrator migrator,
  required NodusSchemaTransition transition,
}) {
  final database = migrator.database;
  if (database is! D) {
    throw StateError(
      'Migration hooks require `$D`, but the migrator owns '
      '`${database.runtimeType}`.',
    );
  }
  return plan.apply(
    NodusMigrationContext<D>(
      migrator: migrator,
      database: database,
      transition: transition,
    ),
  );
}
