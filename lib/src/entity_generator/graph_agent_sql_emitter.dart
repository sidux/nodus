import 'dart:convert';

import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'action_requirements.dart';
import 'check_ins.dart';
import 'member_operations.dart';
import 'member_operations_sql.dart'
    show MemberOperationsSql, derivedActionPatch;
import 'model.dart';
import 'sql_emitter.dart' show activeReferrerExistsSql, principalByIdExpression;

/// Emits the agent tool surface of a graph target.
///
/// `list_agent_tools()` describes every tool an [AgentAccess] declaration
/// grants, and `run_agent_tool(name, arguments)` runs one as the signed-in
/// account. Reads run under row-level security and writes go through the
/// generated push functions, so an agent meets exactly the rules every other
/// client meets. A token issued to an OAuth client (an agent) is confined to
/// the declared entities: other tables refuse it, other push functions refuse
/// it, and graph pulls refuse it.
String emitAgentSurfaceSql(EntityGraphSpec graph) {
  final entities = [
    for (final entity in graph.entities)
      if (entity.agentAccess != null) _AgentEntity.resolve(entity, graph),
  ];
  final writable = <String>{};
  final readable = <String>{};
  for (final entity in entities) {
    readable.add(entity.spec.className);
    if (entity.writes) writable.add(entity.spec.className);
    for (final text in entity.texts) {
      readable
        ..add(text.document.className)
        ..add(text.content.className);
      if (entity.writes) {
        writable
          ..add(text.document.className)
          ..add(text.content.className);
      }
    }
  }
  final operations = [
    for (final root in graph.entities)
      if (root.memberOperations != null)
        MemberOperationsSql(ResolvedMemberOperations.of(root, graph)),
  ];
  for (final operations in operations) {
    if (!operations.resolved.operations.any((op) => op.agentTool != null)) {
      continue;
    }
    writable
      ..add(operations.root.className)
      ..add(operations.member.className);
  }
  final checkIns = [
    for (final log in graph.entities)
      if (log.checkIns != null) ResolvedCheckIns.of(log, graph),
  ];
  for (final log in checkIns) {
    if (log.spec.checkInTool == null &&
        log.spec.undoTool == null &&
        log.spec.logTool == null) {
      continue;
    }
    writable
      ..add(log.log.className)
      ..add(log.undo.className);
    if (log.answers case final answers?) writable.add(answers.className);
  }
  final tools = [
    for (final entity in entities) ...entity.tools(entities),
    for (final operations in operations)
      ..._operationTools(operations, entities),
    for (final log in checkIns) ..._checkInTools(log, entities),
  ];
  final buffer = StringBuffer()
    ..writeln('-- Agent tool surface: what AI agents signed in through OAuth')
    ..writeln('-- may read and change, derived from AgentAccess declarations.')
    ..writeln()
    ..writeln(_helpersSql(writable));
  for (final entity in entities) {
    buffer.writeln(entity.rowFunctionSql());
  }
  for (final text in {
    for (final entity in entities)
      if (entity.writes)
        for (final text in entity.texts) text.content.className: text,
  }.values) {
    buffer.writeln(text.replaceFunctionSql());
  }
  for (final tool in tools) {
    buffer.writeln(tool.functionSql);
  }
  buffer
    ..writeln(_manifestSql(tools))
    ..writeln(_dispatcherSql(tools))
    ..writeln(
      _authenticatedOnlySql([
        'public.is_agent_request()',
        'public.agent_writable(text)',
        'public.agent_require_access()',
        'public.agent_uuid(text, text)',
        'public.agent_now()',
        'public.agent_check_arguments(jsonb, text[])',
        'public.agent_required(jsonb, text)',
        'public.agent_flags_in(jsonb, text[])',
        'public.agent_flags_out(bigint, text[])',
        for (final entity in entities)
          '${entity.rowFunction}(public.${entity.table})',
        for (final text in {
          for (final entity in entities)
            if (entity.writes)
              for (final text in entity.texts) text.content.className: text,
        }.values)
          '${text.replaceFunction}(uuid, text, text, text)',
        for (final tool in tools) 'public.agent_tool_${tool.name}(jsonb)',
      ]),
    )
    ..write(_scopePoliciesSql(graph, readable));
  return buffer.toString();
}

/// Generated agent functions run only for signed-in accounts.
String _authenticatedOnlySql(List<String> signatures) => [
  for (final signature in signatures)
    'revoke all on function $signature from $_apiRoles;\n'
        'grant execute on function $signature to authenticated;',
].join('\n');

const _apiRoles = 'public, anon, authenticated, service_role';

String _helpersSql(Set<String> writable) {
  final writableList = writable.isEmpty
      ? 'array[]::text[]'
      : 'array[${(writable.toList()..sort()).map(_quote).join(', ')}]';
  return '''
create or replace function public.is_agent_request()
returns boolean
language sql
stable
set search_path = ''
as \$\$
  select coalesce(auth.jwt() ? 'client_id', false)
\$\$;

create or replace function public.agent_session_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as \$\$
  select exists (
    select 1 from auth.sessions session
    where session.id = nullif(auth.jwt() ->> 'session_id', '')::uuid
  )
\$\$;

create or replace function public.agent_writable(p_entity_type text)
returns boolean
language sql
immutable
set search_path = ''
as \$\$
  select p_entity_type = any($writableList)
\$\$;

create or replace function public.agent_require_access()
returns void
language plpgsql
stable
set search_path = ''
as \$\$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_session_active() then
    raise exception 'Agent access was revoked' using errcode = '42501';
  end if;
end;
\$\$;

create or replace function public.agent_uuid(p_key text, p_part text)
returns uuid
language sql
volatile
set search_path = ''
as \$\$
  select case
    when p_key is null then gen_random_uuid()
    else md5(auth.uid()::text || ':' || p_key || ':' || p_part)::uuid
  end
\$\$;

create or replace function public.agent_now()
returns jsonb
language sql
stable
set search_path = ''
as \$\$
  select to_jsonb(to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
\$\$;

create or replace function public.agent_check_arguments(
  p_arguments jsonb,
  p_allowed text[]
)
returns void
language plpgsql
immutable
set search_path = ''
as \$\$
declare
  unknown_key text;
begin
  if jsonb_typeof(p_arguments) <> 'object' then
    raise exception 'Tool arguments must be an object' using errcode = '22023';
  end if;
  select key into unknown_key
  from jsonb_object_keys(p_arguments) key
  where not (key = any(p_allowed))
  limit 1;
  if unknown_key is not null then
    raise exception 'Unknown argument "%"', unknown_key using errcode = '22023';
  end if;
end;
\$\$;

create or replace function public.agent_required(
  p_arguments jsonb,
  p_name text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as \$\$
begin
  if not (p_arguments ? p_name) or jsonb_typeof(p_arguments -> p_name) = 'null' then
    raise exception 'Missing argument "%"', p_name using errcode = '22023';
  end if;
  return p_arguments -> p_name;
end;
\$\$;

create or replace function public.agent_flags_in(
  p_value jsonb,
  p_names text[]
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as \$\$
declare
  bits bigint := 0;
  name text;
begin
  -- A missing argument stays missing, so its default applies.
  if p_value is null then
    return null;
  end if;
  if jsonb_typeof(p_value) = 'null' then
    return 'null'::jsonb;
  end if;
  if jsonb_typeof(p_value) <> 'array' then
    raise exception 'Expected a list of %', array_to_string(p_names, ', ')
      using errcode = '22023';
  end if;
  for name in select jsonb_array_elements_text(p_value) loop
    if array_position(p_names, name) is null then
      raise exception 'Unknown value "%": expected %', name, array_to_string(p_names, ', ')
        using errcode = '22023';
    end if;
    bits := bits | (1::bigint << (array_position(p_names, name) - 1));
  end loop;
  return to_jsonb(bits);
end;
\$\$;

create or replace function public.agent_flags_out(
  p_value bigint,
  p_names text[]
)
returns jsonb
language sql
immutable
set search_path = ''
as \$\$
  select case when p_value is null then 'null'::jsonb else coalesce((
    select jsonb_agg(flag.name order by flag.position)
    from unnest(p_names) with ordinality as flag(name, position)
    where p_value & (1::bigint << (flag.position::integer - 1)) <> 0
  ), '[]'::jsonb) end
\$\$;

revoke all on function public.agent_session_active() from $_apiRoles;
grant execute on function public.agent_session_active() to authenticated;
''';
}

final class _AgentEntity {
  _AgentEntity(this.spec, this.texts, this.graph);

  factory _AgentEntity.resolve(EntitySpec spec, EntityGraphSpec graph) {
    final texts = <_AgentTextField>[];
    for (final field in spec.fields) {
      final reference = field.reference;
      if (!field.isComposition || reference == null) continue;
      final document = graph.entities.singleWhere(
        (entity) => entity.className == reference.targetClassName,
      );
      final content = graph.entities.where((entity) {
        final text = entity.agentText;
        if (text == null) return false;
        final documentField = entity.fields.singleWhere(
          (candidate) => candidate.name == text.documentFieldName,
        );
        return documentField.reference?.targetClassName == document.className;
      }).firstOrNull;
      if (content == null) continue;
      texts.add(_AgentTextField(field, document, content));
    }
    final entity = _AgentEntity(spec, texts, graph);
    entity._validate();
    return entity;
  }

  final EntitySpec spec;
  final List<_AgentTextField> texts;
  final EntityGraphSpec graph;

  AgentAccessSpec get access => spec.agentAccess!;
  String get table => spec.tableName;
  String get singular => snakeCase(spec.className);
  String get label => _words(spec.className);
  List<ActionSpec> get actions => [
    for (final action in spec.ordinaryActions)
      if (action.agentTool) action,
  ];
  bool get writes =>
      (spec.orderScopeTransferAction?.agentTool ?? false) ||
      access.create ||
      access.edit ||
      access.link ||
      access.remove ||
      access.archive ||
      actions.isNotEmpty;

  _AgentTextField? textFor(FieldSpec field) =>
      texts.where((text) => text.field == field).firstOrNull;

  void _validate() {
    if (writes && spec.ownership != Ownership.separate) {
      throw InvalidGenerationSourceError(
        'AgentAccess writes need an entity with a separate owner: '
        '${spec.className}.',
      );
    }
    if (access.create && !spec.canCreatePublicly) {
      throw InvalidGenerationSourceError(
        'AgentAccess.create needs an entity its owner creates: '
        '${spec.className}.',
      );
    }
    if (access.edit && !spec.canUpdate) {
      throw InvalidGenerationSourceError(
        'AgentAccess.edit needs an entity with an update grant: '
        '${spec.className}.',
      );
    }
    for (final field in createPayloadFields) {
      if (_createArgument(field) || textFor(field) != null) continue;
      if (field.nullable || field.persistedDefaultValue != null) continue;
      if (access.create) {
        throw InvalidGenerationSourceError(
          'AgentAccess.create cannot fill `${field.name}` of '
          '${spec.className}: give it a default or a supported type.',
        );
      }
    }
    for (final text in texts) {
      if (writes && !text.content.hasSoftDeletableCapability) {
        throw InvalidGenerationSourceError(
          'AgentText content must be soft-deletable to be replaced: '
          '${text.content.className}.',
        );
      }
    }
  }

  /// Fields the generated create sends, apart from identity and order.
  List<FieldSpec> get createPayloadFields => [
    for (final field in spec.createFields)
      if (field != spec.ownerField &&
          field.name != EntityConventions.orderRankFieldName)
        field,
  ];

  bool _createArgument(FieldSpec field) =>
      !access.hidden.contains(field.name) &&
      spec.createParameters.contains(field) &&
      (!spec.isActionTarget(field) || field.reference != null) &&
      !field.isComposition &&
      _schema(field, spec) != null;

  List<FieldSpec> get createArguments => [
    for (final field in createPayloadFields)
      if (_createArgument(field)) field,
  ];

  List<FieldSpec> get editArguments => [
    for (final field in spec.draftEditableFields)
      if (!field.isComposition &&
          !access.hidden.contains(field.name) &&
          _schema(field, spec) != null)
        field,
    if (spec.canUpdate)
      for (final variant in spec.persistedVariants)
        for (final field in variant.storageFields)
          if (!spec.draftEditableFields.contains(field) &&
              spec.isPatchable(field) &&
              !access.hidden.contains(field.name) &&
              _schema(field, spec) != null)
            field,
  ];

  List<FieldSpec> get outputFields => [
    for (final field in spec.fields)
      if (field.name != EntityConventions.orderRankFieldName &&
          field.name != EntityConventions.serverVersionFieldName &&
          field.name != EntityConventions.deletedAtFieldName &&
          !field.isComposition)
        field,
  ];

  String get rowFunction => 'public.agent_${table}_row';

  String rowFunctionSql() {
    final pairs = <String>[
      for (final field in outputFields)
        "${_quote(field.name)}, ${_outSql(field, 'p_row.${field.columnName}')}",
      for (final text in texts)
        "${_quote(text.argumentName)}, ${text.readSql('p_row')}",
    ];
    final objects = <String>[];
    for (var start = 0; start < pairs.length; start += 40) {
      final end = start + 40 < pairs.length ? start + 40 : pairs.length;
      objects.add(
        'jsonb_build_object(\n    ${pairs.sublist(start, end).join(',\n    ')}\n  )',
      );
    }
    return '''
create or replace function $rowFunction(p_row public.$table)
returns jsonb
language sql
stable
set search_path = ''
as \$\$
  select ${objects.join(' || ')}
\$\$;
''';
  }

  String get liveCondition =>
      spec.hasSoftDeletableCapability ? 'item.deleted_at is null' : 'true';

  String get recencyColumn {
    final updated = spec.fields.where((field) => field.autoUpdated).firstOrNull;
    if (updated != null) return updated.columnName;
    final created = spec.fields
        .where((field) => field.name == EntityConventions.createdAtFieldName)
        .firstOrNull;
    return created?.columnName ?? spec.idField.columnName;
  }

  List<_AgentTool> tools(List<_AgentEntity> all) => [
    _listTool(),
    _getTool(all),
    if (access.create) _createTool(),
    if (access.edit) _editTool(),
    for (final action in actions) _actionTool(action),
    if (spec.orderScopeTransferAction case final transfer?
        when transfer.agentTool)
      _transferTool(transfer),
    if (access.link) ..._linkTools(),
    if (access.remove) ..._removeTools(),
    if (access.archive) ..._archiveTools(),
    if (access.reorder) _moveTool(),
  ];

  /// Moves a row within its ordered list: first, last, or next to another
  /// row of the same list.
  _AgentTool _moveTool() {
    if (!spec.hasOrderedCapability) {
      throw InvalidGenerationSourceError(
        'AgentAccess.reorder needs an ordered entity: ${spec.className}.',
      );
    }
    final name = 'move_$singular';
    final id = spec.idField.columnName;
    final scope = [
      for (final field in spec.orderScopeFieldNames ?? const <String>[])
        spec.fields.singleWhere((candidate) => candidate.name == field),
    ];
    final sameList = [
      'candidate.${spec.ownerField.columnName} = current_row.${spec.ownerField.columnName}',
      for (final field in scope)
        'candidate.${field.columnName} is not distinct from current_row.${field.columnName}',
      if (spec.hasSoftDeletableCapability) 'candidate.deleted_at is null',
    ].join(' and ');
    final properties = <String, Object?>{
      'id': {'type': 'string', 'format': 'uuid'},
      'beforeId': {
        'type': 'string',
        'format': 'uuid',
        'description': 'Place it just before this $label of the same list.',
      },
      'afterId': {
        'type': 'string',
        'format': 'uuid',
        'description': 'Place it just after this $label of the same list.',
      },
      'placement': {
        'type': 'string',
        'enum': ['first', 'last'],
        'description': 'Place it first or last instead.',
      },
    };
    return _AgentTool(
      name: name,
      title: 'Move ${_words(spec.className)}',
      description:
          'Moves a $label within its list: before or after another $label of '
          'the same list, or first or last. Name exactly one of beforeId, '
          'afterId, placement.',
      properties: properties,
      required: const ['id'],
      readOnly: false,
      destructive: false,
      idempotent: true,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
  anchor public.$table;
  placement text;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
  if num_nonnulls(p_arguments ->> 'beforeId', p_arguments ->> 'afterId', p_arguments ->> 'placement') <> 1 then
    raise exception 'Name exactly one of beforeId, afterId, placement' using errcode = '22023';
  end if;
${_selectRowSql('current_row')}
  placement := coalesce(p_arguments ->> 'placement', case when p_arguments ? 'beforeId' then 'before' else 'after' end);
  if placement not in ('first', 'last', 'before', 'after') then
    raise exception 'Unknown placement "%"', placement using errcode = '22023';
  end if;
  if placement in ('before', 'after') then
    select * into anchor from public.$table candidate
    where candidate.$id = coalesce(p_arguments ->> 'beforeId', p_arguments ->> 'afterId')::uuid
      and candidate.$id <> current_row.$id and $sameList;
    if anchor.$id is null then
      raise exception 'The $label to move next to is not in the same list' using errcode = '22023';
    end if;
  end if;
${_pushSql(spec, operation: 'command', command: 'moveInOrder', entityId: 'current_row.$id', patch: "'placement', placement, 'anchorId', to_jsonb(anchor.$id), 'scopeBaseVersion', 0", base: 'current_row.${spec.serverVersionField.columnName}')}
  select * into current_row from public.$table item where item.$id = current_row.$id;
  return $rowFunction(current_row);
end;
\$\$;
''',
    );
  }

  /// Delete and restore tools: a hierarchy goes with its descendants, and a
  /// restore brings back only what that removal took.
  List<_AgentTool> _removeTools() {
    if (!spec.hasSoftDeletableCapability) {
      throw InvalidGenerationSourceError(
        'AgentAccess.remove needs a soft-deletable entity: ${spec.className}.',
      );
    }
    final parent = spec.hierarchyParentField;
    final id = spec.idField.columnName;
    final properties = <String, Object?>{
      'id': {'type': 'string', 'format': 'uuid'},
    };
    String delete(
      String entityId,
      String stamp, {
      String indent = '  ',
    }) => _pushSql(
      spec,
      operation: 'delete',
      entityId: entityId,
      patch: "'deletedAt', $stamp",
      base:
          '(select item.${spec.serverVersionField.columnName} from public.$table item where item.$id = $entityId)',
      indent: indent,
    );
    final lift = parent != null && spec.agentAccess!.liftChildren;
    final scope = [
      for (final field in spec.orderScopeTransferFields)
        "${_quote(field.name)}, to_jsonb(current_row.${field.columnName})",
    ].join(', ');
    final descendants = parent == null
        ? ''
        : lift
        ? '''
  for child_id in
    select child.$id from public.$table child
    where child.${parent.columnName} = current_row.$id and child.deleted_at is null
    order by child.order_rank, child.$id
  loop
${_pushSql(spec, operation: 'command', entityId: 'child_id', patch: "'targetScope', jsonb_build_object($scope), 'placement', 'last', 'sourceScopeBaseVersion', 0, 'targetScopeBaseVersion', 0", base: '(select item.${spec.serverVersionField.columnName} from public.$table item where item.$id = child_id)', command: 'transferInOrder', indent: '    ')}
  end loop;'''
        : '''
  for child_id in
    with recursive tree as (
      select item.$id, 0 as depth from public.$table item where item.$id = current_row.$id
      union all
      select child.$id, tree.depth + 1 from public.$table child
      join tree on child.${parent.columnName} = tree.$id
      where child.deleted_at is null
    )
    select tree.$id from tree where tree.$id <> current_row.$id order by tree.depth desc
  loop
${delete('child_id', 'public.agent_now()', indent: '    ')}
    removed := removed + 1;
  end loop;''';
    final restoredDescendants = parent == null || lift
        ? ''
        : '''
  for child_id in
    with recursive tree as (
      select item.$id, 0 as depth from public.$table item where item.$id = current_row.$id
      union all
      select child.$id, tree.depth + 1 from public.$table child
      join tree on child.${parent.columnName} = tree.$id
      where child.deleted_at is not null
        and child.deleted_at >= current_row.deleted_at - interval '3 seconds'
    )
    select tree.$id from tree where tree.$id <> current_row.$id order by tree.depth
  loop
${delete('child_id', "'null'::jsonb", indent: '    ')}
    restored := restored + 1;
  end loop;''';
    final parentCheck = parent == null
        ? ''
        : '''
  if current_row.${parent.columnName} is not null and not exists (
    select 1 from public.$table parent_row
    where parent_row.$id = current_row.${parent.columnName} and parent_row.deleted_at is null
  ) then
    raise exception 'Restore the parent entity before this hierarchy.' using errcode = '22023';
  end if;''';
    final deleteName = 'delete_$singular';
    final restoreName = 'restore_$singular';
    final hierarchy = parent == null
        ? ''
        : lift
        ? '; what is under it moves up a level'
        : ' with everything under it';
    return [
      _AgentTool(
        name: deleteName,
        title: 'Delete ${_words(spec.className)}',
        description:
            'Deletes a $label$hierarchy. It can be brought back with '
            '$restoreName.$_summary',
        properties: properties,
        required: const ['id'],
        readOnly: false,
        destructive: true,
        idempotent: true,
        functionSql:
            '''
create or replace function public.agent_tool_$deleteName(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
  child_id uuid;
  removed integer := 1;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array['id']);
${_selectRowSql('current_row')}
$descendants
${delete('current_row.$id', 'public.agent_now()')}
  return jsonb_build_object('deleted', removed);
end;
\$\$;
''',
      ),
      _AgentTool(
        name: restoreName,
        title: 'Restore ${_words(spec.className)}',
        description:
            'Brings back a deleted $label$hierarchy that was deleted with '
            'it.',
        properties: properties,
        required: const ['id'],
        readOnly: false,
        destructive: false,
        idempotent: true,
        functionSql:
            '''
create or replace function public.agent_tool_$restoreName(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
  child_id uuid;
  restored integer := 1;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array['id']);
  select * into current_row from public.$table item
  where item.$id = (public.agent_required(p_arguments, 'id') #>> '{}')::uuid
    and item.deleted_at is not null;
  if not found then
    raise exception 'Deleted $label not found' using errcode = 'P0002';
  end if;
$parentCheck
${delete('current_row.$id', "'null'::jsonb")}
$restoredDescendants
  select * into current_row from public.$table item where item.$id = current_row.$id;
  return $rowFunction(current_row) || jsonb_build_object('restored', restored);
end;
\$\$;
''',
      ),
    ];
  }

  /// Archive and unarchive tools: a hierarchy goes with the descendants the
  /// caller owns, and unarchiving brings back those archived with it.
  List<_AgentTool> _archiveTools() {
    final archived = spec.archivedAtField;
    if (archived == null) {
      throw InvalidGenerationSourceError(
        'AgentAccess.archive needs an archivable entity: ${spec.className}.',
      );
    }
    final parent = spec.hierarchyParentField;
    final id = spec.idField.columnName;
    final column = archived.columnName;
    final ownerColumn = spec.ownerField.columnName;
    final live = spec.hasSoftDeletableCapability
        ? ' and child.deleted_at is null'
        : '';
    String patch(
      String entityId,
      String value, {
      String indent = '    ',
    }) => _pushSql(
      spec,
      operation: 'patch',
      entityId: entityId,
      patch: "${_quote(archived.name)}, $value",
      base:
          '(select item.${spec.serverVersionField.columnName} from public.$table item where item.$id = $entityId)',
      indent: indent,
    );
    String tree(String condition, {required bool deepestFirst}) =>
        parent == null
        ? 'select current_row.$id'
        : '''
    with recursive tree as (
      select current_row.$id, 0 as depth
      union all
      select child.$id, tree.depth + 1 from public.$table child
      join tree on child.${parent.columnName} = tree.$id
      where child.$ownerColumn = auth.uid()$live and $condition
    )
    select tree.$id from tree order by tree.depth${deepestFirst ? ' desc' : ''}''';
    String tool(String name, String body) =>
        '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
  child_id uuid;
  stamp jsonb := public.agent_now();
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array['id']);
${_selectRowSql('current_row')}
$body
  select * into current_row from public.$table item where item.$id = current_row.$id;
  return $rowFunction(current_row);
end;
\$\$;
''';
    final hierarchy = parent == null ? '' : ' with what is under it';
    final archiveName = 'archive_$singular';
    final unarchiveName = 'unarchive_$singular';
    return [
      _AgentTool(
        name: archiveName,
        title: 'Archive ${_words(spec.className)}',
        description:
            'Archives a $label$hierarchy, out of the way but kept; '
            '$unarchiveName brings it back.',
        properties: const {
          'id': {'type': 'string', 'format': 'uuid'},
        },
        required: const ['id'],
        readOnly: false,
        destructive: false,
        idempotent: true,
        functionSql: tool(archiveName, '''
  if current_row.$column is null then
    for child_id in ${tree('child.$column is null', deepestFirst: true)} loop
${patch('child_id', 'stamp')}
    end loop;
  end if;'''),
      ),
      _AgentTool(
        name: unarchiveName,
        title: 'Unarchive ${_words(spec.className)}',
        description:
            'Brings back an archived $label$hierarchy that was archived '
            'with it.',
        properties: const {
          'id': {'type': 'string', 'format': 'uuid'},
        },
        required: const ['id'],
        readOnly: false,
        destructive: false,
        idempotent: true,
        functionSql: tool(unarchiveName, '''
  if current_row.$column is not null then
    for child_id in ${tree("child.$column >= current_row.$column - interval '3 seconds'", deepestFirst: false)} loop
${patch('child_id', "'null'::jsonb")}
    end loop;
  end if;'''),
      ),
    ];
  }

  /// The tool of an action that moves the row into another order scope,
  /// such as under another parent: it lands last there, and the server
  /// refuses a cycle or a parent the caller cannot reach.
  _AgentTool _transferTool(ActionSpec action) {
    final name = '${snakeCase(action.methodName)}_$singular';
    final fields = {for (final field in spec.fields) field.name: field};
    final targets = [
      for (final parameter in action.parameters) fields[parameter.fieldName]!,
    ];
    final properties = <String, Object?>{
      'id': {'type': 'string', 'format': 'uuid'},
      for (final field in targets)
        field.name:
            _schema(field, spec) ??
            (throw InvalidGenerationSourceError(
              'AgentTool parameter `${field.name}` of '
              '${spec.className}.${action.methodName} has an unsupported type.',
            )),
    };
    final scope = targets
        .map(
          (field) =>
              "${_quote(field.name)}, coalesce(p_arguments -> ${_quote(field.name)}, 'null'::jsonb)",
        )
        .join(', ');
    final unchanged = targets
        .map(
          (field) =>
              "current_row.${field.columnName}::text is not distinct from (p_arguments ->> ${_quote(field.name)})",
        )
        .join(' and ');
    return _AgentTool(
      name: name,
      title: '${_capitalized(_words(action.methodName))} $label',
      description:
          '${action.documentation?.replaceAll('\n', ' ') ?? '${_capitalized(_words(action.methodName))} a $label.'}$_summary',
      properties: properties,
      required: const ['id'],
      readOnly: false,
      destructive: false,
      idempotent: true,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
${_selectRowSql('current_row')}
  if not ($unchanged) then
${_pushSql(spec, operation: 'command', entityId: 'current_row.${spec.idField.columnName}', patch: "'targetScope', jsonb_build_object($scope), 'placement', 'last', 'sourceScopeBaseVersion', 0, 'targetScopeBaseVersion', 0", base: 'current_row.${spec.serverVersionField.columnName}', command: 'transferInOrder', indent: '    ')}
  end if;
  select * into current_row from public.$table item where item.${spec.idField.columnName} = current_row.${spec.idField.columnName};
  return $rowFunction(current_row);
end;
\$\$;
''',
    );
  }

  /// The link and unlink tools of an activatable relationship.
  List<_AgentTool> _linkTools() {
    final relationship =
        spec.activeRelationship ??
        (throw InvalidGenerationSourceError(
          'AgentAccess.link needs an activatable relationship: '
          '${spec.className}.',
        ));
    final owner = relationship.ownerReference;
    final target = relationship.targetReference;
    String role(FieldSpec field) =>
        snakeCase(field.name.replaceAll(RegExp(r'Id$'), ''));
    final ownerRole = role(owner);
    final targetRole = role(target);
    final properties = <String, Object?>{
      owner.name: {
        'type': 'string',
        'format': 'uuid',
        'description': 'The ${_words(ownerRole)}.',
      },
      target.name: {
        'type': 'string',
        'format': 'uuid',
        'description': 'The ${_words(targetRole)}.',
      },
    };
    final ordered = spec.hasOrderedCapability ? 'last' : null;
    final ownerTable = owner.reference!.targetTableName;
    final find =
        '''
  select * into current_row from public.$table item
  where item.${owner.columnName} = (public.agent_required(p_arguments, ${_quote(owner.name)}) #>> '{}')::uuid
    and item.${target.columnName} = (public.agent_required(p_arguments, ${_quote(target.name)}) #>> '{}')::uuid
    and $liveCondition;''';
    final created = [
      "'${spec.idField.name}', to_jsonb(link_id)",
      if (spec.ownerField.name != owner.name)
        "'${spec.ownerField.name}', to_jsonb((select owner_row.owner_id from public.$ownerTable owner_row where owner_row.id = (p_arguments ->> ${_quote(owner.name)})::uuid))",
      "${_quote(owner.name)}, p_arguments -> ${_quote(owner.name)}",
      "${_quote(target.name)}, p_arguments -> ${_quote(target.name)}",
      "${_quote(relationship.activeField.name)}, 'true'::jsonb",
      for (final field in createPayloadFields)
        if (field.name != owner.name &&
            field.name != target.name &&
            field.name != relationship.activeField.name &&
            field.name != spec.ownerField.name)
          '${_quote(field.name)}, ${_defaultSql(field)}',
    ];
    String tool(String name, String body) =>
        '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
  link_id uuid;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
$find
$body
  select * into current_row from public.$table item
  where item.${owner.columnName} = (p_arguments ->> ${_quote(owner.name)})::uuid
    and item.${target.columnName} = (p_arguments ->> ${_quote(target.name)})::uuid
    and $liveCondition;
  return case when current_row.${spec.idField.columnName} is null then null else $rowFunction(current_row) end;
end;
\$\$;
''';
    final linkName =
        spec.agentAccess!.linkTool ?? 'link_${targetRole}_to_$ownerRole';
    final unlinkName =
        spec.agentAccess!.unlinkTool ?? 'unlink_${targetRole}_from_$ownerRole';
    final active = relationship.activeField.columnName;
    return [
      _AgentTool(
        name: linkName,
        title: 'Link ${_words(targetRole)} to ${_words(ownerRole)}',
        description:
            'Links a ${_words(targetRole)} to a ${_words(ownerRole)}; '
            'linking it again changes nothing.$_summary',
        properties: properties,
        required: [owner.name, target.name],
        readOnly: false,
        destructive: false,
        idempotent: true,
        functionSql: tool(linkName, '''
  if current_row.${spec.idField.columnName} is null then
    link_id := gen_random_uuid();
${_pushSql(spec, operation: 'create', entityId: 'link_id', patch: created.join(', '), ordered: ordered, indent: '    ')}
  elsif not current_row.$active then
${_pushSql(spec, operation: 'patch', entityId: 'current_row.${spec.idField.columnName}', patch: "${_quote(relationship.activeField.name)}, 'true'::jsonb", base: 'current_row.${spec.serverVersionField.columnName}', indent: '    ')}
  end if;'''),
      ),
      _AgentTool(
        name: unlinkName,
        title: 'Unlink ${_words(targetRole)} from ${_words(ownerRole)}',
        description:
            'Unlinks a ${_words(targetRole)} from a ${_words(ownerRole)}; '
            'both stay, only the link ends.',
        properties: properties,
        required: [owner.name, target.name],
        readOnly: false,
        destructive: false,
        idempotent: true,
        functionSql: tool(unlinkName, '''
  if current_row.${spec.idField.columnName} is not null and current_row.$active then
${_pushSql(spec, operation: 'patch', entityId: 'current_row.${spec.idField.columnName}', patch: "${_quote(relationship.activeField.name)}, 'false'::jsonb", base: 'current_row.${spec.serverVersionField.columnName}', indent: '    ')}
  end if;'''),
      ),
    ];
  }

  String get _summary {
    final doc = spec.documentation;
    if (doc == null) return '';
    return ' ${doc.split('\n\n').first.replaceAll('\n', ' ')}';
  }

  _AgentTool _listTool() {
    final name = 'list_$table';
    final properties = <String, Object?>{
      'query': {
        'type': 'string',
        'description': 'Only rows whose text contains this, ignoring case.',
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 200,
        'description': 'At most this many rows; 50 by default.',
      },
    };
    final conditions = <String>[liveCondition];
    if (spec.hasArchivableCapability) {
      properties['includeArchived'] = {
        'type': 'boolean',
        'description': 'Include archived rows; false by default.',
      };
      conditions.add(
        "(coalesce((p_arguments ->> 'includeArchived')::boolean, false) "
        'or item.archived_at is null)',
      );
    }
    for (final field in spec.fields) {
      if (field.isEnum && field.persistedVariantName == null) {
        properties[field.name] = {
          'type': 'array',
          'items': {'type': 'string', 'enum': field.enumWireValues},
          'description': 'Only rows with one of these values.',
        };
        conditions.add(
          "(not p_arguments ? ${_quote(field.name)} or item.${field.columnName}::text = any("
          "array(select jsonb_array_elements_text(p_arguments -> ${_quote(field.name)}))))",
        );
      } else if (field.reference != null &&
          !field.isComposition &&
          field != spec.ownerField) {
        properties[field.name] = {
          'type': ['string', 'null'],
          'format': 'uuid',
          'description':
              'Only rows whose ${_words(field.name)} is this id, or null for none.',
        };
        conditions.add(
          "(not p_arguments ? ${_quote(field.name)} or item.${field.columnName} "
          "is not distinct from (p_arguments ->> ${_quote(field.name)})::uuid)",
        );
      }
    }
    final searchable = [
      for (final field in spec.fields)
        if (field.sqlType == SqlType.text &&
            !field.isEnum &&
            field.reference == null)
          'item.${field.columnName}',
      for (final text in texts) text.readSql('item'),
    ];
    if (searchable.isNotEmpty) {
      conditions.add(
        '(search_text is null or ${searchable.map((value) => 'strpos(lower(coalesce($value, \'\')), lower(search_text)) > 0').join(' or ')})',
      );
    }
    return _AgentTool(
      name: name,
      title: 'List ${_plural(label)}',
      description:
          'Lists the ${_plural(label)} you can see, most recently changed first.$_summary',
      properties: properties,
      required: const [],
      readOnly: true,
      destructive: false,
      idempotent: true,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as \$\$
declare
  row_limit integer;
  search_text text := nullif(btrim(p_arguments ->> 'query'), '');
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
  row_limit := least(greatest(coalesce((p_arguments ->> 'limit')::integer, 50), 1), 200);
  return coalesce((
    select jsonb_agg($rowFunction(picked.item) order by (picked.item).$recencyColumn desc)
    from (
      select item from public.$table item
      where ${conditions.join('\n        and ')}
      order by item.$recencyColumn desc
      limit row_limit
    ) picked
  ), '[]'::jsonb);
end;
\$\$;
''',
    );
  }

  String _selectRowSql(String into, {bool write = true}) {
    final locks = [
      for (final name in spec.agentAccess?.locked ?? const <String>[])
        switch (spec.fields.singleWhere((field) => field.name == name)) {
          final field when field.dartType == 'bool' =>
            'coalesce($into.${field.columnName}, false)',
          final field => '$into.${field.columnName} is not null',
        },
    ];
    final lockSql = !write || locks.isEmpty
        ? ''
        : '''

  if ${locks.join(' or ')} then
    raise exception 'This $label is provided by the app and cannot be changed by an agent'
      using errcode = '42501';
  end if;''';
    return '''
  select * into $into from public.$table item
  where item.${spec.idField.columnName} = (public.agent_required(p_arguments, 'id') #>> '{}')::uuid
    and $liveCondition;
  if not found then
    raise exception '${_capitalized(label)} not found' using errcode = 'P0002';
  end if;$lockSql''';
  }

  /// Refuses the action while its declared linked work is unfinished.
  String _requirementsSql(ActionSpec action) {
    final resolved = ResolvedActionRequirements(spec, action, graph);
    final message = resolved.message('%');
    return '''
  declare
    unfinished text[] := ${resolved.sqlFunction}(current_row.${spec.idField.columnName});
    kind text := case when cardinality(unfinished) = 1 then unfinished[1] else 'items' end;
  begin
    if cardinality(unfinished) > 0 then
      raise exception ${_quote(message)}, kind, kind using errcode = '22023';
    end if;
  end;''';
  }

  /// The function giving the caller's root for today, when this entity is
  /// a `DayRoot`.
  String? get _dayRootFunction =>
      spec.memberOperations?.root == null ? null : 'public.${table}_for_today';

  _AgentTool _getTool(List<_AgentEntity> all) {
    final name = 'get_$singular';
    final related = <String>[];
    for (final other in all) {
      final pointing = [
        for (final field in other.spec.fields)
          if (field.reference?.targetClassName == spec.className &&
              !field.isComposition &&
              field != other.spec.ownerField)
            field,
      ];
      for (final field in pointing) {
        final active = other.spec.activeRelationship;
        // Rows of the same table, or of a table that points here through
        // several fields, are told apart by the field that points here.
        final key = lowerCamelCase(
          other.table == table || pointing.length > 1
              ? '${other.table}_by_${field.columnName}'
              : other.table,
        );
        related.add('''
${_quote(key)}, coalesce((
      select jsonb_agg(${other.rowFunction}(picked.related))
      from (
        select related from public.${other.table} related
        where related.${field.columnName} = current_row.${spec.idField.columnName}
          and ${other.spec.hasSoftDeletableCapability ? 'related.deleted_at is null' : 'true'}
          ${active == null ? '' : 'and related.${active.activeField.columnName}'}
        limit 100
      ) picked
    ), '[]'::jsonb)''');
      }
    }
    final relatedSql = related.isEmpty
        ? ''
        : ' || jsonb_build_object(\n    ${related.join(',\n    ')}\n  )';
    return _AgentTool(
      name: name,
      title: 'Get $label',
      description:
          'Reads one $label by id, with the rows that point to it.$_summary',
      properties: {
        'id': {'type': 'string', 'format': 'uuid'},
      },
      required: const ['id'],
      readOnly: true,
      destructive: false,
      idempotent: true,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as \$\$
declare
  current_row public.$table;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array['id']);
${_selectRowSql('current_row', write: false)}
  return $rowFunction(current_row)$relatedSql;
end;
\$\$;
''',
    );
  }

  _AgentTool _createTool() {
    final name = 'create_$singular';
    final properties = <String, Object?>{
      for (final field in createArguments) field.name: _schema(field, spec),
      for (final text in texts) text.argumentName: text.schema,
      'idempotencyKey': {
        'type': 'string',
        'description':
            'Any unique string. Retrying with the same key returns the first '
            'result instead of creating a second $label.',
      },
    };
    final required = [
      for (final field in createArguments)
        if (!field.nullable && field.persistedDefaultValue == null) field.name,
    ];
    final textVariables = [
      for (final text in texts)
        '  ${text.variable} uuid := public.agent_uuid(idempotency_key, ${_quote('$name:${text.field.name}')});',
    ];
    final documents = [
      for (final text in texts)
        _pushSql(
          text.document,
          operation: 'create',
          entityId: text.variable,
          patch: [
            "${_quote(text.document.idField.name)}, to_jsonb(${text.variable})",
            for (final field in text.document.createFields)
              "${_quote(field.name)}, ${field == text.document.ownerField ? 'to_jsonb(auth.uid())' : _defaultSql(field)}",
          ].join(', '),
          operationKey: "'$name:${text.field.name}:create'",
        ),
    ];
    final payload = [
      "${_quote(spec.idField.name)}, to_jsonb(new_id)",
      "${_quote(spec.ownerField.name)}, to_jsonb(auth.uid())",
      for (final field in createPayloadFields)
        if (textFor(field) case final text?)
          "${_quote(field.name)}, to_jsonb(${text.variable})"
        else if (_createArgument(field))
          "${_quote(field.name)}, ${field.nullable || field.persistedDefaultValue != null ? "coalesce(${_inSql(field, "p_arguments -> ${_quote(field.name)}")}, ${_defaultSql(field)})" : _inSql(field, "public.agent_required(p_arguments, ${_quote(field.name)})")}"
        else
          "${_quote(field.name)}, ${_defaultSql(field)}",
    ];
    final contents = [
      for (final text in texts)
        '''
  if p_arguments ? ${_quote(text.argumentName)} then
    perform ${text.replaceFunction}(${text.variable}, p_arguments ->> ${_quote(text.argumentName)}, idempotency_key, ${_quote('$name:${text.argumentName}')});
  end if;''',
    ];
    return _AgentTool(
      name: name,
      title: 'Create $label',
      description: 'Creates a $label owned by you.$_summary',
      properties: properties,
      required: required,
      readOnly: false,
      destructive: false,
      idempotent: false,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  idempotency_key text := nullif(p_arguments ->> 'idempotencyKey', '');
  new_id uuid := public.agent_uuid(idempotency_key, ${_quote('$name:id')});
${textVariables.join('\n')}
  current_row public.$table;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
${documents.join('\n')}
${_pushSql(spec, operation: 'create', entityId: 'new_id', patch: payload.join(',\n        '), operationKey: "'$name:create'", ordered: spec.hasOrderedCapability ? 'first' : null)}
${contents.join('\n')}
  select * into current_row from public.$table item where item.${spec.idField.columnName} = new_id;
  return $rowFunction(current_row);
end;
\$\$;
''',
    );
  }

  _AgentTool _editTool() {
    final name = 'edit_$singular';
    final properties = <String, Object?>{
      'id': {'type': 'string', 'format': 'uuid'},
      for (final field in editArguments) field.name: _schema(field, spec),
      for (final text in texts) text.argumentName: text.schema,
    };
    final contents = [
      for (final text in texts)
        '''
  if p_arguments ? ${_quote(text.argumentName)} then
    perform ${text.replaceFunction}(current_row.${text.field.columnName}, p_arguments ->> ${_quote(text.argumentName)}, null, ${_quote('$name:${text.argumentName}')});
  end if;''',
    ];
    final variantGroups = <String, List<FieldSpec>>{};
    final plain = <FieldSpec>[];
    for (final field in editArguments) {
      final variant = field.persistedVariantName;
      if (variant == null) {
        plain.add(field);
      } else {
        variantGroups.putIfAbsent(variant, () => []).add(field);
      }
    }
    final patchParts = [
      for (final field in plain)
        "case when p_arguments ? ${_quote(field.name)} then jsonb_build_object(${_quote(field.name)}, ${_inSql(field, "p_arguments -> ${_quote(field.name)}")}) else '{}'::jsonb end",
      // Setting one part of a variant clears its other parts.
      for (final fields in variantGroups.values)
        "case when p_arguments ?| array[${fields.map((field) => _quote(field.name)).join(', ')}] then jsonb_build_object(${fields.map((field) => "${_quote(field.name)}, coalesce(${_inSql(field, "p_arguments -> ${_quote(field.name)}")}, 'null'::jsonb)").join(', ')}) else '{}'::jsonb end",
    ];
    return _AgentTool(
      name: name,
      title: 'Edit $label',
      description:
          'Changes the given fields of a $label and leaves the others as they are.$_summary',
      properties: properties,
      required: const ['id'],
      readOnly: false,
      destructive: false,
      idempotent: true,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
  patch jsonb;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
${_selectRowSql('current_row')}
  patch := ${patchParts.isEmpty ? "'{}'::jsonb" : patchParts.join('\n    || ')};
  if patch <> '{}'::jsonb then
${_pushSql(spec, operation: 'patch', entityId: 'current_row.${spec.idField.columnName}', patchSql: 'patch', base: 'current_row.${spec.serverVersionField.columnName}', indent: '    ')}
  end if;
${contents.join('\n')}
  select * into current_row from public.$table item where item.${spec.idField.columnName} = current_row.${spec.idField.columnName};
  return $rowFunction(current_row);
end;
\$\$;
''',
    );
  }

  /// The function that refuses a status change the graph keeps behind a
  /// check while that check is pending: relationship editors may not take
  /// such an edge, and an agent acting for the user may not either, so the
  /// check is not skipped. It reads the checks with the generated guards'
  /// rights, since an agent cannot read them itself. Null when [action]
  /// takes no such edge.
  ({String name, String sql})? _checkedEdges(ActionSpec action) {
    final conditions = <String>[];
    for (final assignment in action.assignments) {
      if (assignment.kind != ActionValueKind.literal) continue;
      final field = spec.fields.firstWhere(
        (candidate) => candidate.name == assignment.fieldName,
      );
      if (field.transitions.isEmpty) continue;
      final target = snakeCase(assignment.literal! as String);
      for (final transition in field.transitions) {
        if (transition.toWire != target ||
            transition.relationshipBlockers.isEmpty) {
          continue;
        }
        final blocked = transition.relationshipBlockers
            .map(
              (blocker) => activeReferrerExistsSql(
                blocker,
                'current_row.${spec.idField.columnName}',
              ),
            )
            .join(' or ');
        conditions.add(
          "(current_row.${field.columnName} = '${transition.fromWire}' and ($blocked))",
        );
      }
    }
    if (conditions.isEmpty) return null;
    final name =
        'public.agent_${snakeCase(action.methodName)}_${singular}_awaits_check';
    // Only about a row the caller may read.
    final readable = {
      for (final grant in spec.security.grants)
        if (grant.operation == RlsOperation.select)
          principalByIdExpression(spec, grant.principal, 'p_id'),
    }.join(' or ');
    return (
      name: name,
      sql:
          '''
create or replace function $name(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as \$\$
  select coalesce((
    select ${conditions.join(' or ')}
    from public.$table current_row
    where current_row.${spec.idField.columnName} = p_id
      and ($readable)
  ), false)
\$\$;

revoke all on function $name(uuid) from $_apiRoles;
grant execute on function $name(uuid) to authenticated;
''',
    );
  }

  _AgentTool _actionTool(ActionSpec action) {
    if (spec.isOrderScopeTransferAction(action)) {
      throw InvalidGenerationSourceError(
        'AgentTool does not support order-scope transfers yet: '
        '${spec.className}.${action.methodName}.',
      );
    }
    final name =
        action.agentToolName ?? '${snakeCase(action.methodName)}_$singular';
    final fields = {for (final field in spec.fields) field.name: field};
    final checked = _checkedEdges(action);
    final today = _dayRootFunction;
    final properties = <String, Object?>{
      'id': {
        'type': 'string',
        'format': 'uuid',
        if (today != null)
          'description': 'The $label; today\'s by default, made when missing.',
      },
      for (final parameter in action.parameters)
        parameter.name:
            _schema(fields[parameter.fieldName]!) ??
            (throw InvalidGenerationSourceError(
              'AgentTool parameter `${parameter.name}` of '
              '${spec.className}.${action.methodName} has an unsupported type.',
            )),
    };
    String parameterJson(String name) =>
        action.parameters
            .singleWhere((parameter) => parameter.name == name)
            .dartType
            .endsWith('?')
        ? "coalesce(p_arguments -> ${_quote(name)}, 'null'::jsonb)"
        : "public.agent_required(p_arguments, ${_quote(name)})";
    final patch = [
      for (final parameter in action.parameters)
        "${_quote(parameter.fieldName)}, ${parameterJson(parameter.name)}",
      ...derivedActionPatch(action, (name) => fields[name]!, parameterJson),
      for (final assignment in action.assignments)
        "${_quote(assignment.fieldName)}, ${switch (assignment.kind) {
          ActionValueKind.literal => _jsonLiteral(fields[assignment.fieldName]!.isEnum && assignment.literal is String ? snakeCase(assignment.literal! as String) : assignment.literal),
          ActionValueKind.clockNow => 'public.agent_now()',
          ActionValueKind.clear => "'null'::jsonb",
        }}",
    ];
    return _AgentTool(
      name: name,
      title: '${_capitalized(_words(action.methodName))} $label',
      description:
          '${action.documentation?.replaceAll('\n', ' ') ?? '${_capitalized(_words(action.methodName))} a $label.'}$_summary',
      properties: properties,
      required: [
        if (today == null) 'id',
        for (final parameter in action.parameters)
          if (!parameter.dartType.endsWith('?')) parameter.name,
      ],
      readOnly: false,
      destructive: false,
      idempotent: false,
      functionSql:
          '''${checked?.sql ?? ''}
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  current_row public.$table;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
${today == null ? '' : "  if p_arguments ->> 'id' is null then\n    p_arguments := p_arguments || jsonb_build_object('id', $today());\n  end if;"}
${_selectRowSql('current_row')}
${[for (final refusal in action.agentRefusals) "  if coalesce(current_row.${fields[refusal.fieldName]!.columnName}, false) then\n    raise exception ${_quote(refusal.message)} using errcode = '42501';\n  end if;"].join('\n')}
${action.requirements.isEmpty ? '' : _requirementsSql(action)}
${checked == null ? '' : '''  if ${checked.name}(current_row.${spec.idField.columnName}) then
    raise exception 'This waits for a check: do it in Grittle so the reviewer is asked'
      using errcode = '42501';
  end if;'''}
${_pushSql(spec, operation: 'patch', entityId: 'current_row.${spec.idField.columnName}', patch: patch.join(', '), base: 'current_row.${spec.serverVersionField.columnName}')}
  select * into current_row from public.$table item where item.${spec.idField.columnName} = current_row.${spec.idField.columnName};
  return $rowFunction(current_row);
end;
\$\$;
''',
    );
  }
}

final class _AgentTextField {
  _AgentTextField(this.field, this.document, this.content);

  final FieldSpec field;
  final EntitySpec document;
  final EntitySpec content;

  AgentTextSpec get text => content.agentText!;

  String get argumentName {
    final name = field.name;
    for (final suffix in ['DocumentId', 'Id']) {
      if (name.endsWith(suffix) && name.length > suffix.length) {
        return name.substring(0, name.length - suffix.length);
      }
    }
    return name;
  }

  String get variable => 'new_${snakeCase(field.name)}';

  FieldSpec _field(String name) =>
      content.fields.singleWhere((field) => field.name == name);

  FieldSpec get documentField => _field(text.documentFieldName);
  FieldSpec get textField => _field(text.textFieldName);

  Map<String, Object?> get schema => {
    'type': 'string',
    'description':
        'Plain text. Replaces the whole ${_words(argumentName)} when given.',
  };

  String readSql(String row) {
    final order = content.hasOrderedCapability
        ? 'content.${content.orderRankField!.columnName}'
        : 'content.${content.idField.columnName}';
    return "(select string_agg(content.${textField.columnName}, '' order by $order) "
        'from public.${content.tableName} content '
        'where content.${documentField.columnName} = $row.${field.columnName}'
        '${content.hasSoftDeletableCapability ? ' and content.deleted_at is null' : ''})';
  }

  String get replaceFunction => 'public.agent_replace_${content.tableName}';

  String replaceFunctionSql() {
    final payload = [
      "${_quote(content.idField.name)}, to_jsonb(new_id)",
      for (final candidate in content.createFields)
        if (candidate.name != EntityConventions.orderRankFieldName)
          "${_quote(candidate.name)}, ${candidate == content.ownerField
              ? 'to_jsonb(auth.uid())'
              : candidate == documentField
              ? 'to_jsonb(p_document_id)'
              : candidate == textField
              ? 'to_jsonb(p_text || ${_quote(text.terminator)})'
              : _defaultSql(candidate)}",
    ];
    for (final candidate in content.createFields) {
      if (candidate.isId ||
          candidate == content.ownerField ||
          candidate == documentField ||
          candidate == textField ||
          candidate.name == EntityConventions.orderRankFieldName ||
          candidate.nullable ||
          candidate.persistedDefaultValue != null) {
        continue;
      }
      throw InvalidGenerationSourceError(
        'AgentText cannot fill `${candidate.name}` of ${content.className}: '
        'give it a default.',
      );
    }
    return '''
create or replace function $replaceFunction(
  p_document_id uuid,
  p_text text,
  p_key text,
  p_part text
)
returns void
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  existing record;
  new_id uuid := public.agent_uuid(p_key, p_part || ':content');
begin
  for existing in
    select content.${content.idField.columnName} as id, content.${content.serverVersionField.columnName} as version
    from public.${content.tableName} content
    where content.${documentField.columnName} = p_document_id and content.deleted_at is null
  loop
${_pushSql(content, operation: 'delete', entityId: 'existing.id', patch: "'deletedAt', public.agent_now()", base: 'existing.version', operationKey: "p_part || ':delete:' || existing.id", keyVariable: 'p_key', indent: '    ')}
  end loop;
  if coalesce(p_text, '') <> '' then
${_pushSql(content, operation: 'create', entityId: 'new_id', patch: payload.join(', '), operationKey: "p_part || ':create'", keyVariable: 'p_key', ordered: content.hasOrderedCapability ? 'last' : null, indent: '    ')}
  end if;
end;
\$\$;
''';
  }
}

final class _AgentTool {
  const _AgentTool({
    required this.name,
    required this.title,
    required this.description,
    required this.properties,
    required this.required,
    required this.readOnly,
    required this.destructive,
    required this.idempotent,
    required this.functionSql,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> properties;
  final List<String> required;
  final bool readOnly;
  final bool destructive;
  final bool idempotent;
  final String functionSql;

  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    },
    'annotations': {
      'title': title,
      'readOnlyHint': readOnly,
      'destructiveHint': destructive,
      'idempotentHint': idempotent,
      'openWorldHint': false,
    },
  };
}

String _pushSql(
  EntitySpec entity, {
  required String operation,
  required String entityId,
  String? patch,
  String? patchSql,
  String base = '0',
  String? operationKey,
  String keyVariable = 'idempotency_key',
  String? ordered,
  String? command,
  String indent = '  ',
}) {
  final commandName = command == null
      ? ''
      : ",\n$indent    'commandName', '$command'";
  final operationId = operationKey == null
      ? 'gen_random_uuid()'
      : 'public.agent_uuid($keyVariable, $operationKey)';
  final orderedCreate = ordered == null
      ? ''
      : ",\n$indent    'orderedCreate', jsonb_build_object('placement', '$ordered', 'scopeBaseVersion', 0)";
  return '''${indent}perform public.push_${entity.tableName}_operations(jsonb_build_array(jsonb_build_object(
$indent    'operationId', $operationId,
$indent    'operation', '$operation',
$indent    'entityType', '${entity.className}',
$indent    'entityId', $entityId,
$indent    'baseServerVersion', $base,
$indent    'protocolVersion', ${entity.protocolVersion}$orderedCreate$commandName,
$indent    'patch', ${patchSql ?? 'jsonb_build_object($patch)'}
$indent  )));''';
}

String _manifestSql(List<_AgentTool> tools) {
  final manifest = const JsonEncoder.withIndent(
    '  ',
  ).convert([for (final tool in tools) tool.toJson()]);
  return '''
create or replace function public.list_agent_tools()
returns jsonb
language sql
immutable
set search_path = ''
as \$\$
  select \$agent_tools\$$manifest\$agent_tools\$::jsonb
\$\$;

revoke all on function public.list_agent_tools() from $_apiRoles;
grant execute on function public.list_agent_tools() to authenticated;
''';
}

String _dispatcherSql(List<_AgentTool> tools) {
  final cases = [
    for (final tool in tools)
      "    when ${_quote(tool.name)} then return public.agent_tool_${tool.name}(arguments);",
  ];
  return '''
create or replace function public.run_agent_tool(
  p_tool text,
  p_arguments jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  arguments jsonb := coalesce(p_arguments, '{}'::jsonb);
begin
  perform public.agent_require_access();
  case p_tool
${cases.join('\n')}
    else raise exception 'Unknown agent tool "%"', p_tool using errcode = '22023';
  end case;
end;
\$\$;

revoke all on function public.run_agent_tool(text, jsonb) from $_apiRoles;
grant execute on function public.run_agent_tool(text, jsonb) to authenticated;
''';
}

/// Tables outside the agent surface refuse agent tokens outright. Generated
/// access helpers are security definers, so permission checks still read
/// them on the agent's behalf.
String _scopePoliciesSql(EntityGraphSpec graph, Set<String> readable) {
  final buffer = StringBuffer();
  for (final entity in graph.entities) {
    if (readable.contains(entity.className)) continue;
    buffer.writeln('''
create policy "${entity.tableName}_agent_scope"
on public.${entity.tableName}
as restrictive
for all
to authenticated
using (not public.is_agent_request())
with check (not public.is_agent_request());
''');
  }
  return buffer.toString();
}

Map<String, Object?>? _schema(FieldSpec field, [EntitySpec? owner]) {
  final variantName = field.persistedVariantName;
  if (variantName != null) {
    final variant = owner?.persistedVariants
        .where((candidate) => candidate.name == variantName)
        .firstOrNull;
    if (variant == null ||
        variant.storageFields.any((f) => f.reference != null)) {
      return null;
    }
  }
  final flags = field.scalarValue?.flags;
  final Map<String, Object?> schema;
  if (flags != null) {
    schema = {
      'type': 'array',
      'items': {'type': 'string', 'enum': flags},
      'uniqueItems': true,
    };
  } else if (field.isEnum) {
    schema = {'type': 'string', 'enum': field.enumWireValues};
  } else {
    schema = switch (field.sqlType) {
      SqlType.text => {
        'type': 'string',
        'minLength': ?field.minLength,
        'maxLength': ?field.maxLength,
      },
      SqlType.uuid => {'type': 'string', 'format': 'uuid'},
      SqlType.boolean => {'type': 'boolean'},
      SqlType.integer => {
        'type': 'integer',
        'minimum': ?field.minValue,
        'maximum': ?field.maxValue,
      },
      SqlType.real => {'type': 'number'},
      SqlType.date => {'type': 'string', 'format': 'date'},
      SqlType.timestampWithTimeZone => {
        'type': 'string',
        'format': 'date-time',
      },
    };
  }
  if (field.nullable) {
    final type = schema['type'];
    schema['type'] = [type, 'null'];
    if (schema['enum'] case final List<Object?> values) {
      schema['enum'] = [...values, null];
    }
  }
  final documentation = field.documentation;
  final notes = [
    ?documentation?.replaceAll('\n', ' '),
    if (variantName != null)
      () {
        final variant = owner!.persistedVariants.firstWhere(
          (candidate) => candidate.name == variantName,
        );
        final choices = [
          for (final variantCase in variant.cases)
            if (variantCase.presenceField case final presence?) presence.name,
        ];
        final empty = variant.emptyCase;
        return 'Part of `$variantName`: set at most one of '
            '${choices.join(', ')}${empty == null ? '' : '; none is ${_caseLabel(empty.className, variant.dartType)}'}.';
      }(),
  ];
  if (notes.isNotEmpty) schema['description'] = notes.join(' ');
  return schema;
}

String _caseLabel(String className, String variantType) {
  final base = variantType.replaceAll('?', '');
  final stem = className.endsWith(base)
      ? className.substring(0, className.length - base.length)
      : className;
  return snakeCase(stem).replaceAll('_', ' ');
}

/// The stored JSON value of agent argument [argument] for [field].
String _inSql(FieldSpec field, String argument) {
  final flags = field.scalarValue?.flags;
  if (flags == null) return argument;
  return 'public.agent_flags_in($argument, array[${flags.map(_quote).join(', ')}])';
}

/// The agent-facing JSON value of [field] stored in [column].
String _outSql(FieldSpec field, String column) {
  final flags = field.scalarValue?.flags;
  if (flags == null) return column;
  return 'public.agent_flags_out($column, array[${flags.map(_quote).join(', ')}])';
}

String _defaultSql(FieldSpec field) {
  final value = field.persistedDefaultValue;
  if (value == null) return "'null'::jsonb";
  return _jsonLiteral(value);
}

String _jsonLiteral(Object? value) =>
    "'${jsonEncode(value).replaceAll("'", "''")}'::jsonb";

String _quote(String value) => "'${value.replaceAll("'", "''")}'";

String _words(String camel) => snakeCase(camel).replaceAll('_', ' ');

String _capitalized(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _plural(String label) => label.endsWith('s')
    ? '${label}es'
    : label.endsWith('y')
    ? '${label.substring(0, label.length - 1)}ies'
    : '${label}s';

/// Agent tools for the member operations of [operations] exposed with
/// `agentTool`: each runs on the caller's root for today, made when missing,
/// and returns that root's live members in order.
List<_AgentTool> _operationTools(
  MemberOperationsSql operations,
  List<_AgentEntity> entities,
) {
  final exposed = [
    for (final operation in operations.resolved.operations)
      if (operation.agentTool != null) operation,
  ];
  if (exposed.isEmpty) return const [];
  final dayRoot =
      operations.dayRoot ??
      (throw InvalidGenerationSourceError(
        'Agent member operations need a DayRoot on '
        '${operations.root.className}.',
      ));
  final member =
      entities
          .where(
            (entity) => entity.spec.className == operations.member.className,
          )
          .firstOrNull ??
      (throw InvalidGenerationSourceError(
        'Agent member operations need AgentAccess on '
        '${operations.member.className}.',
      ));
  Map<String, Object?> keySchema(String description) => {
    'type': 'string',
    'format': 'uuid',
    'description': description,
  };
  String keyLabel(String argument) =>
      _words(argument.replaceAll(RegExp(r'Id$'), ''));
  String keyObject(String prefix) =>
      'jsonb_strip_nulls(jsonb_build_object(${[for (final name in operations.keyArguments) "${_quote(name)}, p_arguments -> ${_quote(_prefixed(prefix, name))}"].join(', ')}))';
  _AgentTool tool(MemberOperationSpec operation) {
    final name = operation.agentTool!;
    final properties = <String, Object?>{
      for (final argument in operations.keyArguments)
        argument: keySchema(
          'The ${keyLabel(argument)} to act on; name exactly one of '
          '${operations.keyArguments.join(', ')}.',
        ),
      for (final parameter in operation.parameters)
        if (parameter.isMember)
          for (final argument in operations.keyArguments)
            _prefixed(parameter.name, argument): keySchema(
              '${parameter.description} Named by ${keyLabel(argument)}.',
            )
        else
          parameter.name: {
            ...?_schema(operations.resolved.field(parameter.fieldName!)),
            'description': parameter.description,
          },
    };
    final arguments = [
      "${_quote(operations.resolved.key.name)}, ${keyObject('')}",
      for (final parameter in operation.parameters)
        if (parameter.isMember)
          "${_quote(parameter.name)}, nullif(${keyObject(parameter.name)}, '{}'::jsonb)"
        else
          "${_quote(parameter.name)}, p_arguments -> ${_quote(parameter.name)}",
    ];
    return _AgentTool(
      name: name,
      title: _capitalized(_words(operation.name)),
      description:
          '${operation.description.replaceAll('\n', ' ')} Returns the '
          "day's ${_words(operations.member.className)}s in order.",
      properties: properties,
      required: const [],
      readOnly: false,
      destructive: false,
      idempotent: false,
      functionSql:
          '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  root_id uuid;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
  root_id := ${dayRoot.function}();
  perform ${operations.function(operation)}(
    root_id,
    jsonb_strip_nulls(jsonb_build_object(${arguments.join(', ')}))
  );
  return coalesce((
    select jsonb_agg(${member.rowFunction}(item) order by item.order_rank, item.id)
    from public.${operations.member.tableName} item
    where item.${operations.rootColumn} = root_id and item.deleted_at is null
  ), '[]'::jsonb);
end;
\$\$;
''',
    );
  }

  return [for (final operation in exposed) tool(operation)];
}

/// Agent tools for a declared check-in log: checking a subject in now and
/// undoing check-ins, each returning the affected log rows.
List<_AgentTool> _checkInTools(
  ResolvedCheckIns checkIns,
  List<_AgentEntity> entities,
) {
  final spec = checkIns.spec;
  if (spec.checkInTool == null &&
      spec.undoTool == null &&
      spec.logTool == null) {
    return const [];
  }
  final log =
      entities
          .where((entity) => entity.spec.className == checkIns.log.className)
          .firstOrNull ??
      (throw InvalidGenerationSourceError(
        'Agent check-in tools need AgentAccess on ${checkIns.log.className}.',
      ));
  final subject = checkIns.subject;
  final subjectLabel = _words(subject.className);
  final subjectArgument = checkIns.subjectField.name;
  final part = checkIns.part;
  Map<String, Object?> schema(FieldSpec field, String description) => {
    ...?_schema(field),
    'description': description,
  };
  final subjectProperty = {
    'type': 'string',
    'format': 'uuid',
    'description': 'The $subjectLabel.',
  };
  String rows(String ids) =>
      "coalesce((select jsonb_agg(${log.rowFunction}(item) order by item.${checkIns.at.columnName} desc) "
      'from public.${checkIns.log.tableName} item where item.id = any($ids)), '
      "'[]'::jsonb)";
  String function(String name, Map<String, Object?> properties, String body) =>
      '''
create or replace function public.agent_tool_$name(p_arguments jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  subject_id uuid;
  ids uuid[];
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
  subject_id := (public.agent_required(p_arguments, ${_quote(subjectArgument)}) #>> '{}')::uuid;
$body
end;
\$\$;
''';
  final agentRefusals = [
    for (final refusal in spec.agentRefusals)
      '  if coalesce((select subject_row.${subject.fields.firstWhere((field) => field.name == refusal.fieldName).columnName} '
          'from public.${subject.tableName} subject_row where subject_row.id = subject_id), false) then\n'
          "    raise exception ${_quote(refusal.message)} using errcode = '42501';\n"
          '  end if;',
  ].join('\n');
  final answers = <String, Object?>{
    if (checkIns.answers != null)
      'answers': {
        'type': 'object',
        'description':
            "Answers to the $subjectLabel's questions, keyed by question id: "
            'a number, text, true or false, a date (YYYY-MM-DD), a date and '
            'time, minutes after midnight for a time, or the chosen option '
            'id. Questions left out keep no answer.',
      },
  };
  final tools = <_AgentTool>[];
  final logTool = spec.logTool;
  if (logTool != null) {
    final properties = <String, Object?>{
      subjectArgument: subjectProperty,
      checkIns.date.name: schema(checkIns.date, 'The past day to log.'),
      part.name: schema(
        part,
        'The part of the day to log; every part the $subjectLabel is '
        'scheduled for by default.',
      ),
      checkIns.at.name: schema(
        checkIns.at,
        'Its time of day is recorded; ${spec.loggedAtHour}:00 by default.',
      ),
      ...answers,
    };
    tools.add(
      _AgentTool(
        name: logTool,
        title: 'Log $subjectLabel day',
        description:
            'Records a $subjectLabel as done on a past day, as the app logs a '
            'missed day: only a day it existed on and was scheduled for, and '
            'parts of the day already logged stay as they are. Returns the '
            'new check-ins.',
        properties: properties,
        required: [subjectArgument, checkIns.date.name],
        readOnly: false,
        destructive: false,
        idempotent: true,
        functionSql: function(
          logTool,
          properties,
          '$agentRefusals\n'
          '  ids := ${checkIns.logDayFunction}(subject_id, p_arguments);\n'
          '  return ${rows('ids')};',
        ),
      ),
    );
  }
  final checkInTool = spec.checkInTool;
  if (checkInTool != null) {
    final properties = <String, Object?>{
      subjectArgument: subjectProperty,
      part.name: schema(
        part,
        'The part of the day to check in for; the current one by default. '
        'Only the current part of the day can be checked in, unless the '
        '$subjectLabel is for the whole day.',
      ),
      for (final field in checkIns.details)
        field.name: schema(field, 'Recorded with the check-in.'),
      ...answers,
    };
    tools.add(
      _AgentTool(
        name: checkInTool,
        title: 'Check in $subjectLabel',
        description:
            'Checks a $subjectLabel in for today with the same rules as the '
            'app: in the current part of the day, only when scheduled then, '
            'and for an interval $subjectLabel only once its interval has '
            'passed. Checking in again updates the check-in. Returns the '
            'check-in.',
        properties: properties,
        required: [subjectArgument],
        readOnly: false,
        destructive: false,
        idempotent: false,
        functionSql: function(checkInTool, properties, '''
$agentRefusals
  ids := array[${checkIns.checkInFunction}(subject_id, p_arguments)];
  return ${rows('ids')} -> 0;'''),
      ),
    );
  }
  final undoTool = spec.undoTool;
  if (undoTool != null) {
    final properties = <String, Object?>{
      subjectArgument: subjectProperty,
      checkIns.date.name: schema(
        checkIns.date,
        'The day to undo; today by default.',
      ),
      part.name: schema(
        part,
        'The part of the day to undo; the current one by default.',
      ),
      checkIns.undoComment.name: schema(
        checkIns.undoComment,
        'Why the check-in is undone, kept with the record of it.',
      ),
    };
    tools.add(
      _AgentTool(
        name: undoTool,
        title: 'Undo $subjectLabel check-in',
        description:
            "Takes back a $subjectLabel's check-ins for a day and part of the "
            'day, or for an interval $subjectLabel its latest check-in, and '
            'records that it was undone. Returns the undone check-ins.',
        properties: properties,
        required: [subjectArgument],
        readOnly: false,
        destructive: true,
        idempotent: false,
        functionSql: function(
          undoTool,
          properties,
          '$agentRefusals\n'
          '  ids := ${checkIns.undoFunction}(subject_id, p_arguments);\n'
          '  return ${rows('ids')};',
        ),
      ),
    );
  }
  return tools;
}

String _prefixed(String prefix, String name) => prefix.isEmpty
    ? name
    : '$prefix${name[0].toUpperCase()}${name.substring(1)}';
