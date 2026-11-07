import 'dart:convert';

import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';

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
  final tools = [for (final entity in entities) ...entity.tools(entities)];
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

revoke all on function public.agent_session_active() from $_apiRoles;
grant execute on function public.agent_session_active() to authenticated;
''';
}

final class _AgentEntity {
  _AgentEntity(this.spec, this.texts);

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
    final entity = _AgentEntity(spec, texts);
    entity._validate();
    return entity;
  }

  final EntitySpec spec;
  final List<_AgentTextField> texts;

  AgentAccessSpec get access => spec.agentAccess!;
  String get table => spec.tableName;
  String get singular => snakeCase(spec.className);
  String get label => _words(spec.className);
  List<ActionSpec> get actions => [
    for (final action in spec.ordinaryActions)
      if (action.agentTool) action,
  ];
  bool get writes => access.create || access.edit || actions.isNotEmpty;

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
    if (access.create && spec.persistedVariants.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'AgentAccess.create does not support persisted variants yet: '
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
      spec.createParameters.contains(field) &&
      (!spec.isActionTarget(field) || field.reference != null) &&
      !field.isComposition &&
      field.persistedVariantName == null &&
      _schema(field) != null;

  List<FieldSpec> get createArguments => [
    for (final field in createPayloadFields)
      if (_createArgument(field)) field,
  ];

  List<FieldSpec> get editArguments => [
    for (final field in spec.draftEditableFields)
      if (!field.isComposition && _schema(field) != null) field,
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
        "${_quote(field.name)}, p_row.${field.columnName}",
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
  ];

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

  String _selectRowSql(String into) =>
      '''
  select * into $into from public.$table item
  where item.${spec.idField.columnName} = (public.agent_required(p_arguments, 'id') #>> '{}')::uuid
    and $liveCondition;
  if not found then
    raise exception '${_capitalized(label)} not found' using errcode = 'P0002';
  end if;''';

  _AgentTool _getTool(List<_AgentEntity> all) {
    final name = 'get_$singular';
    final related = <String>[];
    for (final other in all) {
      for (final field in other.spec.fields) {
        final reference = field.reference;
        if (reference == null ||
            reference.targetClassName != spec.className ||
            field.isComposition ||
            field == other.spec.ownerField) {
          continue;
        }
        final active = other.spec.activeRelationship;
        final key = lowerCamelCase(
          other.table == table
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
${_selectRowSql('current_row')}
  return $rowFunction(current_row)$relatedSql;
end;
\$\$;
''',
    );
  }

  _AgentTool _createTool() {
    final name = 'create_$singular';
    final properties = <String, Object?>{
      for (final field in createArguments) field.name: _schema(field),
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
          "${_quote(field.name)}, ${field.nullable || field.persistedDefaultValue != null ? "coalesce(p_arguments -> ${_quote(field.name)}, ${_defaultSql(field)})" : "public.agent_required(p_arguments, ${_quote(field.name)})"}"
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
      for (final field in editArguments) field.name: _schema(field),
      for (final text in texts) text.argumentName: text.schema,
    };
    final contents = [
      for (final text in texts)
        '''
  if p_arguments ? ${_quote(text.argumentName)} then
    perform ${text.replaceFunction}(current_row.${text.field.columnName}, p_arguments ->> ${_quote(text.argumentName)}, null, ${_quote('$name:${text.argumentName}')});
  end if;''',
    ];
    final editable = editArguments
        .map((field) => _quote(field.name))
        .join(', ');
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
  select coalesce(jsonb_object_agg(argument.key, argument.value), '{}'::jsonb) into patch
  from jsonb_each(p_arguments) argument
  where argument.key = any(array[${editable.isEmpty ? '' : editable}]::text[]);
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

  _AgentTool _actionTool(ActionSpec action) {
    if (spec.isOrderScopeTransferAction(action)) {
      throw InvalidGenerationSourceError(
        'AgentTool does not support order-scope transfers yet: '
        '${spec.className}.${action.methodName}.',
      );
    }
    final name = '${snakeCase(action.methodName)}_$singular';
    final fields = {for (final field in spec.fields) field.name: field};
    final properties = <String, Object?>{
      'id': {'type': 'string', 'format': 'uuid'},
      for (final parameter in action.parameters)
        parameter.name:
            _schema(fields[parameter.fieldName]!) ??
            (throw InvalidGenerationSourceError(
              'AgentTool parameter `${parameter.name}` of '
              '${spec.className}.${action.methodName} has an unsupported type.',
            )),
    };
    final patch = [
      for (final parameter in action.parameters)
        "${_quote(parameter.fieldName)}, ${parameter.dartType.endsWith('?') ? "coalesce(p_arguments -> ${_quote(parameter.name)}, 'null'::jsonb)" : "public.agent_required(p_arguments, ${_quote(parameter.name)})"}",
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
        'id',
        for (final parameter in action.parameters)
          if (!parameter.dartType.endsWith('?')) parameter.name,
      ],
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
  current_row public.$table;
begin
  perform public.agent_require_access();
  perform public.agent_check_arguments(p_arguments, array[${properties.keys.map(_quote).join(', ')}]);
${_selectRowSql('current_row')}
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
  String indent = '  ',
}) {
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
$indent    'protocolVersion', ${entity.protocolVersion}$orderedCreate,
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

Map<String, Object?>? _schema(FieldSpec field) {
  if (field.persistedVariantName != null) return null;
  final Map<String, Object?> schema;
  if (field.isEnum) {
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
  if (documentation != null) {
    schema['description'] = documentation.replaceAll('\n', ' ');
  }
  return schema;
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
