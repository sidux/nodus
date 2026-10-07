import 'package:nodus/src/tool/change_snapshot_backfill.dart';
import 'package:test/test.dart';

void main() {
  const entityTypeByTable = {
    'daily_plans': 'DailyPlan',
    'goal_members': 'GoalMember',
  };

  test('a column added to an entity table is filled into older change '
      'snapshots from the live row, else its default', () {
    final sql = appendChangeSnapshotBackfills(
      'SET check_function_bodies = false;\n\n'
      'ALTER TABLE public.daily_plans\n'
      '  ADD COLUMN energy_overflow bigint DEFAULT 0 NOT NULL;\n',
      entityTypeByTable: entityTypeByTable,
    );

    expect(
      sql,
      contains(
        "update public.local_entity_changes change\n"
        "set record = change.record || jsonb_build_object(\n"
        "  'energy_overflow',\n"
        "  coalesce(\n"
        "    (select to_jsonb(live.energy_overflow) from public.daily_plans "
        "live where live.id = change.entity_id),\n"
        "    to_jsonb((0)::bigint)\n"
        "  )\n"
        ")\n"
        "where change.entity_type = 'DailyPlan'\n"
        "  and not change.is_revocation\n"
        "  and not (change.record ? 'energy_overflow');",
      ),
    );
  });

  test('every column of a multi-column addition is filled, and a nullable '
      'one without a default becomes null', () {
    final sql = appendChangeSnapshotBackfills(
      'ALTER TABLE public.goal_members ADD COLUMN can_edit boolean '
      "DEFAULT true NOT NULL, ADD COLUMN note text;",
      entityTypeByTable: entityTypeByTable,
    );

    expect(sql, contains("to_jsonb((true)::boolean)"));
    expect(sql, contains("'note',"));
    expect(sql, contains("'null'::jsonb"));
    expect(sql, contains("change.entity_type = 'GoalMember'"));
  });

  test('a column added to a table no entity syncs needs no backfill', () {
    const migration =
        'ALTER TABLE public.account_media_cleanups\n'
        '  ADD COLUMN attempts integer DEFAULT 0 NOT NULL;\n';

    expect(
      appendChangeSnapshotBackfills(
        migration,
        entityTypeByTable: entityTypeByTable,
      ),
      migration,
    );
  });
}
