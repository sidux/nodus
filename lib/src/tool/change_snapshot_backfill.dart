/// Pulls replay each change's row as it was recorded, so a column added to an
/// entity table is missing from every change recorded before it. Clients
/// without a default for it reject such changes, so a migration that adds
/// one also fills it into those snapshots: from the row as it is now, else
/// from the column's default.
String appendChangeSnapshotBackfills(
  String migrationSql, {
  required Map<String, String> entityTypeByTable,
}) {
  final backfills = [
    for (final column in _addedColumns(migrationSql))
      if (entityTypeByTable[column.table] case final entityType?)
        _backfillSql(column, entityType),
  ];
  if (backfills.isEmpty) return migrationSql;
  return '${migrationSql.trimRight()}\n\n'
      '-- Changes recorded before these columns existed replay without them.\n'
      '${backfills.join('\n\n')}\n';
}

typedef _AddedColumn = ({
  String table,
  String column,
  String type,
  String? defaultExpression,
});

final _alterTable = RegExp(
  r'ALTER TABLE (?:ONLY )?(?:"?public"?\.)?"?(\w+)"?\s+((?:ADD COLUMN[^;]*?)+);',
  caseSensitive: false,
  dotAll: true,
);

final _addColumn = RegExp(
  r'ADD COLUMN (?:IF NOT EXISTS )?"?(\w+)"?\s+(.+?)(?=,\s*ADD COLUMN|$)',
  caseSensitive: false,
  dotAll: true,
);

final _default = RegExp(
  r'\bDEFAULT\s+(.+?)(?=\s+(?:NOT\s+NULL|NULL|CHECK|REFERENCES|UNIQUE|PRIMARY|GENERATED|COLLATE|CONSTRAINT)\b|$)',
  caseSensitive: false,
  dotAll: true,
);

final _typeEnd = RegExp(
  r'\s+(?:DEFAULT|NOT\s+NULL|NULL|CHECK|REFERENCES|UNIQUE|PRIMARY|GENERATED|COLLATE|CONSTRAINT)\b',
  caseSensitive: false,
);

Iterable<_AddedColumn> _addedColumns(String sql) sync* {
  for (final statement in _alterTable.allMatches(sql)) {
    final table = statement.group(1)!;
    for (final add in _addColumn.allMatches(statement.group(2)!)) {
      final definition = add.group(2)!.trim().replaceFirst(RegExp(r',$'), '');
      final typeEnd = _typeEnd.firstMatch(definition);
      final type =
          (typeEnd == null
                  ? definition
                  : definition.substring(0, typeEnd.start))
              .trim();
      yield (
        table: table,
        column: add.group(1)!,
        type: type,
        defaultExpression: _default.firstMatch(definition)?.group(1)?.trim(),
      );
    }
  }
}

String _backfillSql(_AddedColumn column, String entityType) {
  final fallback = column.defaultExpression == null
      ? "'null'::jsonb"
      : 'to_jsonb((${column.defaultExpression})::${column.type})';
  return '''update public.local_entity_changes change
set record = change.record || jsonb_build_object(
  '${column.column}',
  coalesce(
    (select to_jsonb(live.${column.column}) from public.${column.table} live where live.id = change.entity_id),
    $fallback
  )
)
where change.entity_type = '$entityType'
  and not change.is_revocation
  and not (change.record ? '${column.column}');''';
}
