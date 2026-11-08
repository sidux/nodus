import 'dart:convert';

import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'member_operations.dart';
import 'model.dart';
import 'sql_emitter.dart' show postgresType;

/// SQL for every declared identity, member operation, and day root, applied
/// through the generated push functions as the calling account.
String emitMemberOperationsSql(EntityGraphSpec graph) {
  final identities = [
    for (final entity in graph.entities)
      if (entity.identity != null) ResolvedIdentity.of(entity),
  ];
  if (identities.isEmpty) return '';
  final buffer = StringBuffer()
    ..writeln('-- Derived identities and member operations declared in Nodus.')
    ..writeln()
    ..writeln(uuidV5Sql);
  final signatures = <String>['public.nodus_uuid_v5(uuid, text)'];
  for (final identity in identities) {
    buffer.writeln(identity.sqlDeclaration());
    signatures.add(identity.sqlSignature);
  }
  for (final root in graph.entities) {
    if (root.memberOperations == null) continue;
    final operations = MemberOperationsSql(
      ResolvedMemberOperations.of(root, graph),
    );
    final dayRoot = operations.dayRoot;
    if (dayRoot != null) {
      buffer.writeln(dayRoot.functionSql());
      signatures.add('${dayRoot.function}()');
    }
    for (final operation in operations.resolved.operations) {
      buffer.writeln(operations.functionSql(operation));
      signatures.add('${operations.function(operation)}(uuid, jsonb)');
    }
  }
  for (final signature in signatures) {
    buffer
      ..writeln(
        'revoke all on function $signature from public, anon, authenticated, '
        'service_role;',
      )
      ..writeln('grant execute on function $signature to authenticated;');
  }
  return buffer.toString();
}

/// The SQL form of one root's declared member operations.
final class MemberOperationsSql {
  MemberOperationsSql(this.resolved)
    : dayRoot = resolved.root.memberOperations!.root == null
          ? null
          : DayRootSql(resolved);

  final ResolvedMemberOperations resolved;
  final DayRootSql? dayRoot;

  EntitySpec get member => resolved.member;
  EntitySpec get root => resolved.root;
  String get memberTable => 'public.${member.tableName}';
  String get rootColumn => resolved.rootReference.columnName;

  String function(MemberOperationSpec operation) =>
      'public.${root.tableName}_${snakeCase(operation.name)}';

  /// Columns that name a member, with the argument key each reads.
  List<(FieldSpec, String)> get keyColumns => [
    if (resolved.key.variant == null)
      (resolved.key.field!, resolved.key.name)
    else
      for (final (_, _, field) in resolved.key.cases) (field, field.name),
  ];

  /// Arguments a caller sends to name a member: the key's own name for a
  /// plain field, or one reference per variant case.
  List<String> get keyArguments => [for (final (_, name) in keyColumns) name];

  String _keyVariable(String prefix, FieldSpec column) =>
      '${prefix}_${column.columnName}';

  String _keyDeclarations(String prefix, String source) => [
    for (final (column, name) in keyColumns)
      '  ${_keyVariable(prefix, column)} ${postgresType(column)} := '
          "nullif($source ->> ${_quote(name)}, '')::${postgresType(column)};",
  ].join('\n');

  String _keyMatch(String row, String prefix) => [
    '$row.$rootColumn = p_root_id',
    for (final (column, _) in keyColumns)
      '$row.${column.columnName} is not distinct from '
          '${_keyVariable(prefix, column)}',
  ].join(' and ');

  String _selectLive(String into, String prefix) =>
      'select * into $into from $memberTable item\n'
      '    where ${_keyMatch('item', prefix)} and item.deleted_at is null\n'
      '    order by item.order_rank, item.id limit 1;';

  String functionSql(MemberOperationSpec operation) {
    final anchors = [
      for (final parameter in operation.parameters)
        if (parameter.isMember) parameter.name,
    ];
    final values = [
      for (final parameter in operation.parameters)
        if (!parameter.isMember)
          '  ${_parameterVariable(parameter.name)} jsonb := '
              "coalesce(p_arguments -> ${_quote(parameter.name)}, 'null'::jsonb);",
    ];
    final keyCount = keyColumns.length;
    final body = StringBuffer();
    _steps(body, operation, operation.steps, '  ');
    return '''
create or replace function ${function(operation)}(
  p_root_id uuid,
  p_arguments jsonb
)
returns void
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  member $memberTable;
  removed $memberTable;
  anchor $memberTable;
  after_row $memberTable;
  before_row $memberTable;
  in_group boolean;
${_keyDeclarations('key', "p_arguments -> ${_quote(resolved.key.name)}")}
${[for (final name in anchors) _keyDeclarations(snakeCase(name), "p_arguments -> ${_quote(name)}")].join('\n')}
${values.join('\n')}
begin
  if not exists (
    select 1 from public.${root.tableName} root_row where root_row.id = p_root_id
  ) then
    raise exception '${_capitalized(_words(root.className))} not found' using errcode = 'P0002';
  end if;
  if num_nonnulls(${[for (final (column, _) in keyColumns) _keyVariable('key', column)].join(', ')}) <> 1 then
    raise exception 'Name the ${_words(member.className)} with exactly one of ${keyArguments.join(', ')}'
      using errcode = '22023';
  end if;${keyCount > 1 ? '' : ''}
  ${_selectLive('member', 'key')}
${body.toString().trimRight()}
end;
\$\$;
''';
  }

  String _parameterVariable(String name) => 'param_${snakeCase(name)}';

  void _steps(
    StringBuffer buffer,
    MemberOperationSpec operation,
    List<MemberStepSpec> steps,
    String indent,
  ) {
    for (final step in steps) {
      switch (step) {
        case RequireStepSpec(:final condition, :final message):
          buffer
            ..writeln(
              '${indent}if not ${_condition(operation, condition, 'member')} then',
            )
            ..writeln(
              "$indent  raise exception ${_quote(message)} using errcode = '22023';",
            )
            ..writeln('${indent}end if;');
        case WhenStepSpec(:final condition, :final then, :final otherwise):
          buffer.writeln(
            '${indent}if ${_condition(operation, condition, 'member')} then',
          );
          _steps(buffer, operation, then, '$indent  ');
          if (otherwise.isNotEmpty) {
            buffer.writeln('${indent}else');
            _steps(buffer, operation, otherwise, '$indent  ');
          }
          buffer.writeln('${indent}end if;');
        case StopStepSpec():
          buffer.writeln('${indent}return;');
        case EnsureMemberStepSpec(:final values, :final reset):
          buffer
            ..writeln('${indent}if member.id is null then')
            ..writeln(
              '$indent  select * into removed from $memberTable item\n'
              '$indent    where ${_keyMatch('item', 'key')} and item.deleted_at is not null\n'
              '$indent    order by item.order_rank, item.id limit 1;',
            )
            ..writeln('$indent  if removed.id is null then')
            ..writeln(
              _push(
                member,
                operation: 'create',
                entityId: _identityCall(),
                patch: _createPatch(operation, values),
                ordered: 'last',
                indent: '$indent    ',
              ),
            )
            ..writeln('$indent  else')
            ..writeln(
              // A soft-delete command clearing its field restores the row.
              _push(
                member,
                operation: 'delete',
                entityId: 'removed.id',
                patch: "'deletedAt', 'null'::jsonb",
                base: 'removed.server_version',
                indent: '$indent    ',
              ),
            );
          if (reset != null) {
            buffer
              ..writeln(_reload('removed', '$indent    '))
              ..writeln(
                _push(
                  member,
                  operation: 'patch',
                  entityId: 'removed.id',
                  patch: _actionPatch(
                    operation,
                    resolved.action(reset),
                    values,
                    fillParameters: true,
                  ),
                  base: 'removed.server_version',
                  indent: '$indent    ',
                ),
              );
          }
          buffer
            ..writeln(_reload('removed', '$indent    '))
            ..writeln(_move('removed', "'last'", 'null', '$indent    '))
            ..writeln('$indent  end if;')
            ..writeln('$indent  ${_selectLive('member', 'key')}')
            ..writeln('${indent}end if;');
        case ActStepSpec(:final action, :final arguments):
          buffer
            ..writeln(
              _push(
                member,
                operation: 'patch',
                entityId: 'member.id',
                patch: _actionPatch(
                  operation,
                  resolved.action(action),
                  arguments,
                  fillParameters: true,
                ),
                base: 'member.server_version',
                indent: indent,
              ),
            )
            ..writeln(_reload('member', indent));
        case PlaceStepSpec(:final group, :final after, :final before):
          if (after == null && before == null) {
            _placeAfterLast(buffer, operation, group, indent);
            break;
          }
          buffer
            ..writeln(
              '${indent}in_group := ${_condition(operation, group, 'member')};',
            )
            ..writeln(
              after == null
                  ? '${indent}after_row := null;'
                  : '$indent${_selectLive('after_row', snakeCase(after))}',
            )
            ..writeln(
              before == null
                  ? '${indent}before_row := null;'
                  : '$indent${_selectLive('before_row', snakeCase(before))}',
            )
            ..writeln(
              '${indent}if ${_sameSide(operation, group, 'after_row')} then',
            )
            ..writeln(_move('member', "'after'", 'after_row.id', '$indent  '))
            ..writeln(
              '${indent}elsif ${_sameSide(operation, group, 'before_row')} then',
            )
            ..writeln(_move('member', "'before'", 'before_row.id', '$indent  '))
            ..writeln(
              '${indent}elsif not in_group and after_row.id is not null and '
              '${_condition(operation, group, 'after_row')} then',
            );
          _placeAfterLast(buffer, operation, group, '$indent  ');
          buffer.writeln('${indent}end if;');
      }
    }
  }

  String _sameSide(
    MemberOperationSpec operation,
    OperationConditionSpec group,
    String row,
  ) =>
      '($row.id is not null and $row.id <> member.id and '
      '${_condition(operation, group, row)} = in_group)';

  void _placeAfterLast(
    StringBuffer buffer,
    MemberOperationSpec operation,
    OperationConditionSpec group,
    String indent,
  ) {
    buffer
      ..writeln(
        '${indent}select * into anchor from $memberTable item\n'
        '$indent  where item.$rootColumn = p_root_id and item.deleted_at is null\n'
        '$indent    and item.id <> member.id and ${_condition(operation, group, 'item')}\n'
        '$indent  order by item.order_rank desc, item.id desc limit 1;',
      )
      ..writeln('${indent}if anchor.id is null then')
      ..writeln(_move('member', "'first'", 'null', '$indent  '))
      ..writeln('${indent}else')
      ..writeln(_move('member', "'after'", 'anchor.id', '$indent  '))
      ..writeln('${indent}end if;');
  }

  String _reload(String row, String indent) =>
      '${indent}select * into $row from $memberTable item '
      'where item.id = $row.id;';

  String _move(String row, String placement, String anchor, String indent) =>
      '${_push(member, operation: 'command', command: 'moveInOrder', entityId: '$row.id', patch: "'placement', $placement, 'anchorId', ${anchor == 'null' ? "'null'::jsonb" : 'to_jsonb($anchor)'}, 'scopeBaseVersion', 0", base: '$row.server_version', indent: indent)}\n'
      '${_reload(row, indent)}';

  String _identityCall() =>
      '${resolved.identity.sqlFunction}(p_root_id, '
      '${[for (final (column, _) in keyColumns) _keyVariable('key', column)].join(', ')})';

  String _createPatch(
    MemberOperationSpec operation,
    Map<String, OperationValueSpec> values,
  ) {
    final keyFields = {for (final (column, _) in keyColumns) column.name};
    final entries = <String>[
      "'${member.idField.name}', to_jsonb(${_identityCall()})",
    ];
    for (final field in member.createFields) {
      if (field.name == EntityConventions.orderRankFieldName ||
          field.name == member.idField.name) {
        continue;
      }
      final String value;
      if (field.name == member.ownerField.name) {
        value =
            'to_jsonb((select root_row.owner_id from public.${root.tableName} '
            'root_row where root_row.id = p_root_id))';
      } else if (field.name == resolved.rootReference.name) {
        value = 'to_jsonb(p_root_id)';
      } else if (keyFields.contains(field.name)) {
        final column = keyColumns
            .firstWhere((entry) => entry.$1.name == field.name)
            .$1;
        value = 'to_jsonb(${_keyVariable('key', column)})';
      } else if (values[field.name] != null) {
        value = _value(operation, values[field.name]!);
      } else {
        value = _defaultJson(field);
      }
      entries.add('${_quote(field.name)}, $value');
    }
    return entries.join(', ');
  }

  String _actionPatch(
    MemberOperationSpec operation,
    ActionSpec action,
    Map<String, OperationValueSpec> arguments, {
    required bool fillParameters,
  }) {
    final entries = <String>[
      for (final parameter in action.parameters)
        '${_quote(parameter.fieldName)}, ${arguments[parameter.name] == null ? _defaultJson(resolved.field(parameter.fieldName)) : _value(operation, arguments[parameter.name]!)}',
      for (final assignment in action.assignments)
        '${_quote(assignment.fieldName)}, ${switch (assignment.kind) {
          ActionValueKind.literal => _jsonLiteral(resolved.field(assignment.fieldName).isEnum && assignment.literal is String ? snakeCase(assignment.literal! as String) : assignment.literal),
          ActionValueKind.clockNow => 'public.agent_now()',
          ActionValueKind.clear => "'null'::jsonb",
        }}',
    ];
    return entries.join(', ');
  }

  String _defaultJson(FieldSpec field) {
    final value = field.persistedDefaultValue;
    if (value == null) {
      if (field.nullable) return "'null'::jsonb";
      throw InvalidGenerationSourceError(
        'A member operation must give `${field.name}` of ${member.className} '
        'a value: it has no default.',
      );
    }
    return _jsonLiteral(value);
  }

  String _value(MemberOperationSpec operation, OperationValueSpec value) =>
      switch (value) {
        MemberFieldValueSpec(:final field) =>
          'to_jsonb(member.${resolved.field(field).columnName})',
        ParameterValueSpec(:final name) => _parameterVariable(name),
        KeyTargetValueSpec() => throw InvalidGenerationSourceError(
          'KeyTarget is only supported in Compare.isTrue.',
        ),
      };

  /// [condition] on the member row variable [row]; false for an empty one.
  String _condition(
    MemberOperationSpec operation,
    OperationConditionSpec condition,
    String row,
  ) {
    switch (condition) {
      case MemberLiveConditionSpec():
        return '($row.id is not null)';
      case NotConditionSpec(:final condition):
        return '(not ${_condition(operation, condition, row)})';
      case AllConditionSpec(:final conditions):
        return '(${conditions.map((part) => _condition(operation, part, row)).join(' and ')})';
      case CompareConditionSpec(
        subject: final value,
        :final kind,
        :final values,
        :final other,
      ):
        String present(OperationValueSpec operand) => switch (operand) {
          MemberFieldValueSpec() => '$row.id is not null',
          ParameterValueSpec(:final name) =>
            "${_parameterVariable(name)} <> 'null'::jsonb",
          KeyTargetValueSpec() => 'true',
        };
        String text(OperationValueSpec operand) => switch (operand) {
          MemberFieldValueSpec(:final field) =>
            '$row.${resolved.field(field).columnName}::text',
          ParameterValueSpec(:final name) =>
            "(${_parameterVariable(name)} #>> '{}')",
          KeyTargetValueSpec() => throw InvalidGenerationSourceError(
            'KeyTarget is only supported in Compare.isTrue.',
          ),
        };
        switch (kind) {
          case CompareKind.isIn:
            final field = resolved.field((value as MemberFieldValueSpec).field);
            return '($row.id is not null and $row.${field.columnName} in '
                '(${values.map((name) => _quote(snakeCase(name))).join(', ')}))';
          case CompareKind.isNull:
            return switch (value) {
              MemberFieldValueSpec(:final field) =>
                '($row.id is not null and $row.${resolved.field(field).columnName} is null)',
              ParameterValueSpec(:final name) =>
                "(${_parameterVariable(name)} = 'null'::jsonb)",
              KeyTargetValueSpec() => throw InvalidGenerationSourceError(
                'KeyTarget is only supported in Compare.isTrue.',
              ),
            };
          case CompareKind.isTrue:
            return switch (value) {
              MemberFieldValueSpec(:final field) =>
                'coalesce($row.id is not null and $row.${resolved.field(field).columnName}, false)',
              ParameterValueSpec(:final name) =>
                "(${_parameterVariable(name)} = 'true'::jsonb)",
              KeyTargetValueSpec() => _keyTarget(value),
            };
          case CompareKind.differs:
            return '(${{present(value), present(other!)}.join(' and ')} and '
                '${text(value)} is distinct from ${text(other)})';
        }
    }
  }

  String _keyTarget(KeyTargetValueSpec value) {
    final (_, field, target, targetField) = resolved.keyTarget(value);
    final key = _keyVariable('key', field);
    return '($key is not null and coalesce((select target.${targetField.columnName} '
        'from public.${target.tableName} target where target.id = $key), false))';
  }
}

/// How agents reach a [DayRootSpec] root: the caller's one for today.
final class DayRootSql {
  DayRootSql(this.resolved) {
    final spec = root.memberOperations!.root!;
    if (root.identity == null) {
      throw InvalidGenerationSourceError(
        'DayRoot needs a DerivedIdentity on ${root.className}.',
      );
    }
    final identity = ResolvedIdentity.of(root);
    if (identity.parts.length != 2 ||
        identity.parts.first.name != root.ownerField.name ||
        identity.parts.last.name != spec.dateFieldName) {
      throw InvalidGenerationSourceError(
        'The DerivedIdentity of ${root.className} must key on its owner and '
        '`${spec.dateFieldName}`.',
      );
    }
  }

  final ResolvedMemberOperations resolved;

  EntitySpec get root => resolved.root;
  DayRootSpec get spec => root.memberOperations!.root!;
  String get function => 'public.${root.tableName}_for_today';

  FieldSpec rootField(String name) =>
      root.fields.where((field) => field.name == name).firstOrNull ??
      (throw InvalidGenerationSourceError(
        '`$name` is not a field of ${root.className}.',
      ));

  EntitySpec get owner => resolved.graph.entities.singleWhere(
    (entity) => entity.className == root.ownerClassName,
  );

  String functionSql() {
    final timezone =
        owner.fields
            .where((field) => field.name == spec.timezoneFieldName)
            .firstOrNull ??
        (throw InvalidGenerationSourceError(
          '`${spec.timezoneFieldName}` is not a field of ${owner.className}.',
        ));
    final date = rootField(spec.dateFieldName);
    final identity = ResolvedIdentity.of(root);
    final starting = <String, String>{};
    for (final entry in spec.initial.entries) {
      starting[entry.key] = _startingSql(entry.value, starting);
    }
    final entries = <String>["'${root.idField.name}', to_jsonb(root_id)"];
    for (final field in root.createFields) {
      if (field.name == EntityConventions.orderRankFieldName ||
          field.name == root.idField.name) {
        continue;
      }
      final String value;
      if (field.name == root.ownerField.name) {
        value = 'to_jsonb(auth.uid())';
      } else if (field.name == date.name) {
        value = 'to_jsonb(today)';
      } else if (starting.containsKey(field.name)) {
        value = 'to_jsonb(starting_${snakeCase(field.name)})';
      } else if (field.persistedDefaultValue != null) {
        value = _jsonLiteral(field.persistedDefaultValue);
      } else if (field.nullable) {
        value = "'null'::jsonb";
      } else {
        throw InvalidGenerationSourceError(
          'DayRoot.initial must give `${field.name}` of ${root.className} a '
          'starting value.',
        );
      }
      entries.add('${_quote(field.name)}, $value');
    }
    final declarations = [
      for (final entry in spec.initial.entries)
        '  starting_${snakeCase(entry.key)} ${postgresType(rootField(entry.key))};',
    ];
    final assignments = [
      for (final entry in starting.entries)
        '    starting_${snakeCase(entry.key)} := ${entry.value};',
    ];
    return '''
create or replace function $function()
returns uuid
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  today date;
  root_id uuid;
${declarations.join('\n')}
begin
  perform public.agent_require_access();
  select (now() at time zone coalesce(
      (select profile.${timezone.columnName} from public.${owner.tableName} profile where profile.id = auth.uid()),
      'UTC'
    ))::date
  into today;
  select root_row.id into root_id from public.${root.tableName} root_row
  where root_row.${root.ownerField.columnName} = auth.uid()
    and root_row.${date.columnName} = today;
  if root_id is not null then
    return root_id;
  end if;
  root_id := ${identity.sqlFunction}(auth.uid(), today);
${assignments.join('\n')}
  perform public.push_${root.tableName}_operations(jsonb_build_array(jsonb_build_object(
    'operationId', gen_random_uuid(),
    'operation', 'create',
    'entityType', '${root.className}',
    'entityId', root_id,
    'baseServerVersion', 0,
    'protocolVersion', ${root.protocolVersion},
    'patch', jsonb_build_object(${entries.join(', ')})
  )));
  return root_id;
end;
\$\$;
''';
  }

  String _startingSql(StartingValueSpec value, Map<String, String> earlier) {
    switch (value) {
      case WeekdayAverageSpec():
        final field = rootField(value.fieldName);
        final present = rootField(value.presentFieldName);
        final date = rootField(spec.dateFieldName);
        final bounds = [
          if (field.minValue != null) field.minValue,
          if (field.maxValue != null) field.maxValue,
        ];
        var average =
            '''coalesce((
      select round(avg(earlier.${field.columnName}))::${postgresType(field)}
      from public.${root.tableName} earlier
      where earlier.${root.ownerField.columnName} = auth.uid()
        and earlier.${date.columnName} >= today - ${value.days}
        and earlier.${date.columnName} < today
        and extract(isodow from earlier.${date.columnName}) = extract(isodow from today)
        and earlier.${present.columnName} is not null
      having count(*) >= ${value.minimum}
    ), ${value.fallback})''';
        if (bounds.length == 2) {
          average = 'least(greatest($average, ${bounds[0]}), ${bounds[1]})';
        }
        return average;
      case BandedSpec():
        final source = earlier[value.fieldName];
        if (source == null) {
          throw InvalidGenerationSourceError(
            'Banded reads `${value.fieldName}`, which needs an earlier '
            'starting value.',
          );
        }
        final variable = 'starting_${snakeCase(value.fieldName)}';
        final cases = [
          for (var index = 0; index < value.bounds.length; index++)
            'when $variable < ${value.bounds[index]} then ${_quote(snakeCase(value.values[index]))}',
        ];
        return 'case ${cases.join(' ')} else ${_quote(snakeCase(value.values.last))} end';
    }
  }
}

String _push(
  EntitySpec entity, {
  required String operation,
  required String entityId,
  required String patch,
  String base = '0',
  String? command,
  String? ordered,
  String indent = '  ',
}) {
  final extra = [
    if (command != null) "'commandName', '$command'",
    if (ordered != null)
      "'orderedCreate', jsonb_build_object('placement', '$ordered', 'scopeBaseVersion', 0)",
  ];
  return '''${indent}perform public.push_${entity.tableName}_operations(jsonb_build_array(jsonb_build_object(
$indent  'operationId', gen_random_uuid(),
$indent  'operation', '$operation',
$indent  'entityType', '${entity.className}',
$indent  'entityId', $entityId,
$indent  'baseServerVersion', $base,
$indent  'protocolVersion', ${entity.protocolVersion},${extra.isEmpty ? '' : '\n$indent  ${extra.join(',\n$indent  ')},'}
$indent  'patch', jsonb_build_object($patch)
$indent)));''';
}

String _jsonLiteral(Object? value) => "${_quote(jsonEncode(value))}::jsonb";

String _quote(String value) => "'${value.replaceAll("'", "''")}'";

String _words(String camel) => snakeCase(camel).replaceAll('_', ' ');

String _capitalized(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
