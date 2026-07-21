import 'dart:convert';

import 'package:nodus/nodus.dart';

import 'model.dart';

const supabaseApiRoles = 'public, anon, authenticated, service_role';

String emitSupabaseSql(
  EntitySpec spec, {
  EntitySpec? activitySource,
  bool includeSharedTables = true,
  bool? includeOrderScopeTable,
  bool includeEntityPull = true,
}) {
  final buffer = StringBuffer()
    ..writeln('-- GENERATED FILE. DO NOT EDIT.')
    ..writeln('-- Source: ${spec.inputImport}')
    ..writeln('-- Entity declarations are the schema source of truth.')
    ..writeln()
    ..writeln('create table if not exists public.${spec.tableName} (');

  final columns = spec.fields.map((field) {
    final clauses = <String>[
      '  ${field.columnName} ${_postgresType(field)}',
      if (!field.nullable) 'not null',
      if (field.isId) 'primary key',
      if (field.name == spec.ownerField.name)
        'references auth.users (id) on delete cascade',
      if (field.isParticipant && field.reference == null)
        'references auth.users (id) on delete cascade',
      if (field.reference case final reference?)
        'references public.${reference.targetTableName} '
            '(${EntityConventions.idColumnName}) on delete '
            '${_postgresDeleteAction(reference.onDelete)} '
            'deferrable initially deferred',
      if (field.name == spec.serverVersionField.name)
        'default 1'
      else if (field.name == EntityConventions.createdAtFieldName &&
          field.serverGenerated)
        'default now()'
      else if (field.autoUpdated)
        'default now()'
      else if (field.defaultValue != null)
        'default ${_sqlDefaultLiteral(field)}',
      if (field.minLength != null)
        "check (char_length(${field.allowWhitespace ? field.columnName : 'btrim(${field.columnName})'}) >= ${field.minLength})",
      if (field.maxLength != null)
        "check (char_length(${field.columnName}) <= ${field.maxLength})",
      if (field.minValue != null)
        'check (${field.columnName} >= ${field.minValue})',
      if (field.maxValue != null)
        'check (${field.columnName} <= ${field.maxValue})',
      if (field.allowedValues.isNotEmpty)
        'check (${field.columnName} in '
            '(${field.allowedValues.map(_sqlLiteral).join(', ')}))',
      if (field.greaterThan case final otherName?)
        'check (${field.columnName} > '
            '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName})',
      if (field.greaterThanOrEqual case final otherName?)
        'check (${field.columnName} >= '
            '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName})',
      if (field.requires case final otherName?)
        'check (${field.columnName} is null or '
            '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName} is not null)',
      if (field.notEqualTo case final otherName?)
        'check (${field.columnName} is null or '
            '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName} is null or '
            '${field.columnName} <> '
            '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName})',
      if (field.isEnum)
        "check (${field.columnName} in (${field.enumWireValues.map(_sqlLiteral).join(', ')}))",
      if (field.name == EntityConventions.orderRankFieldName)
        "check (${field.columnName} ~ '^[0-9]{78}\$' and "
            "${field.columnName}::numeric > 0 and "
            "${field.columnName}::numeric < "
            "${GeneratedOrderRanks.upperBoundaryValue}::numeric)",
    ];
    return clauses.join(' ');
  }).toList();
  for (final group in spec.exclusiveFieldGroups) {
    final terms = group.fields
        .map((name) {
          final column = spec.fields
              .singleWhere((field) => field.name == name)
              .columnName;
          return '(($column is not null)::integer)';
        })
        .join(' + ');
    columns.add('  check (($terms) ${group.allowNone ? '<=' : '='} 1)');
  }
  for (final index in spec.compoundIndexes.where(
    (candidate) => candidate.unordered,
  )) {
    final other = spec.fields.singleWhere(
      (field) => field.name == index.fields.single,
    );
    columns.add(
      '  check (${spec.ownerField.columnName} <> ${other.columnName})',
    );
  }
  buffer
    ..writeln(columns.join(',\n'))
    ..writeln(');')
    ..writeln();

  final autoUpdated = spec.fields
      .where((field) => field.autoUpdated)
      .firstOrNull;
  if (autoUpdated != null) {
    buffer
      ..writeln(
        'create or replace function public.touch_${spec.tableName}_${autoUpdated.columnName}()',
      )
      ..writeln(
        'returns trigger language plpgsql set search_path = \'\' as \$\$',
      )
      ..writeln('begin')
      ..writeln('  new.${autoUpdated.columnName} := now();')
      ..writeln('  return new;')
      ..writeln('end;')
      ..writeln('\$\$;')
      ..writeln(
        'revoke all on function public.touch_${spec.tableName}_${autoUpdated.columnName}() '
        'from public, anon, authenticated, service_role;',
      )
      ..writeln(
        'drop trigger if exists ${spec.tableName}_touch_${autoUpdated.columnName} '
        'on public.${spec.tableName};',
      )
      ..writeln(
        'create trigger ${spec.tableName}_touch_${autoUpdated.columnName} '
        'before update on public.${spec.tableName} for each row execute '
        'function public.touch_${spec.tableName}_${autoUpdated.columnName}();',
      )
      ..writeln();
  }

  final serverManaged = spec.fields
      .where((field) => field.isServerManaged)
      .toList(growable: false);
  if (serverManaged.isNotEmpty) {
    final changedPredicate = serverManaged
        .map(
          (field) =>
              'new.${field.columnName} is distinct from old.${field.columnName}',
        )
        .join(' or ');
    buffer
      ..writeln(
        'create or replace function public.version_${spec.tableName}_server_changes()',
      )
      ..writeln(
        'returns trigger language plpgsql set search_path = \'\' as \$\$',
      )
      ..writeln('begin')
      ..writeln(
        '  if new.${spec.serverVersionField.columnName} = '
        'old.${spec.serverVersionField.columnName}',
      )
      ..writeln('      and ($changedPredicate) then')
      ..writeln(
        '    new.${spec.serverVersionField.columnName} := '
        'old.${spec.serverVersionField.columnName} + 1;',
      )
      ..writeln('  end if;')
      ..writeln('  return new;')
      ..writeln('end;')
      ..writeln('\$\$;')
      ..writeln(
        'revoke all on function public.version_${spec.tableName}_server_changes() '
        'from $supabaseApiRoles;',
      )
      ..writeln(
        'drop trigger if exists ${spec.tableName}_version_server_changes '
        'on public.${spec.tableName};',
      )
      ..writeln(
        'create trigger ${spec.tableName}_version_server_changes '
        'before update on public.${spec.tableName} for each row execute '
        'function public.version_${spec.tableName}_server_changes();',
      )
      ..writeln();
  }

  for (final index in spec.postgresIndexes) {
    final unique = index.unique ? 'unique ' : '';
    final columns = spec.indexColumns(index);
    final terms = index.unordered
        ? ['least(${columns.join(', ')})', 'greatest(${columns.join(', ')})']
        : columns;
    final name = spec.indexName(index);
    final condition = index.condition;
    final where = index.activeOnly
        ? ' where ${EntityConventions.deletedAtColumnName} is null'
        : condition == null
        ? ''
        : ' where ${spec.fields.singleWhere((field) => field.name == condition.field).columnName} '
              'in (${condition.values.map(_sqlLiteral).join(', ')})';
    buffer.writeln(
      'create ${unique}index if not exists '
      '$name '
      'on public.${spec.tableName} (${terms.join(', ')})$where;',
    );
  }

  _emitCollaborationTable(buffer, spec);
  _emitAccessReferenceFunction(buffer, spec);
  _emitRelationshipAccessPlaceholders(buffer, spec);
  _emitRls(buffer, spec, activitySource: activitySource);
  _emitSyncInfrastructure(
    buffer,
    spec,
    includeSharedTables: includeSharedTables,
    includeOrderScopeTable: includeOrderScopeTable ?? spec.hasOrderedCapability,
  );
  _emitEntityFunctions(
    buffer,
    spec,
    activitySource: activitySource,
    includePull: includeEntityPull,
  );
  return buffer.toString();
}

void _emitRelationshipAccessPlaceholders(StringBuffer buffer, EntitySpec spec) {
  for (final operation in spec.relationshipAccessOperations) {
    buffer
      ..writeln()
      ..writeln(
        'create or replace function public.is_${spec.tableName}_relationship_${operation.name}('
        'p_id uuid)',
      )
      ..writeln('returns boolean language sql immutable security definer')
      ..writeln("set search_path = '' as \$\$ select false; \$\$;")
      ..writeln(
        'revoke all on function public.is_${spec.tableName}_relationship_${operation.name}(uuid) '
        'from $supabaseApiRoles;',
      );
  }
}

void _emitCollaborationTable(StringBuffer buffer, EntitySpec spec) {
  final collaboration = spec.security.collaboration;
  if (collaboration == null || collaboration.isWorkflow) {
    final ownerColumn = spec.ownerField.columnName;
    buffer
      ..writeln()
      ..writeln(
        'create or replace function public.is_${spec.tableName}_owner('
        'p_id uuid)',
      )
      ..writeln('returns boolean language sql stable security definer')
      ..writeln("set search_path = '' as \$\$")
      ..writeln(
        '  select exists (select 1 from public.${spec.tableName} entity '
        'where entity.${spec.idField.columnName} = p_id and '
        'entity.$ownerColumn = auth.uid());',
      )
      ..writeln('\$\$;')
      ..writeln(
        'create or replace function public.is_${spec.tableName}_collaborator('
        'p_id uuid)',
      )
      ..writeln('returns boolean language sql immutable security definer')
      ..writeln("set search_path = '' as \$\$ select false; \$\$;")
      ..writeln(
        'revoke all on function public.is_${spec.tableName}_owner(uuid) '
        'from $supabaseApiRoles;',
      )
      ..writeln(
        'revoke all on function public.is_${spec.tableName}_collaborator(uuid) '
        'from $supabaseApiRoles;',
      )
      ..writeln(
        'grant execute on function public.is_${spec.tableName}_owner(uuid) '
        'to authenticated;',
      )
      ..writeln(
        'grant execute on function public.is_${spec.tableName}_collaborator(uuid) '
        'to authenticated;',
      );
    if (collaboration?.hasAdditionalReadableStates ?? false) {
      buffer
        ..writeln(
          'create or replace function public.is_${spec.tableName}_viewer('
          'p_id uuid)',
        )
        ..writeln('returns boolean language sql immutable security definer')
        ..writeln("set search_path = '' as \$\$ select false; \$\$;")
        ..writeln(
          'revoke all on function public.is_${spec.tableName}_viewer(uuid) '
          'from $supabaseApiRoles;',
        );
    }
    _emitParticipantFunction(buffer, spec);
    return;
  }
  final activeField = collaboration.activeField!;
  buffer
    ..writeln()
    ..writeln(
      'create table if not exists public.${collaboration.membershipTable} (',
    )
    ..writeln(
      '  ${collaboration.entityForeignKey} uuid not null references '
      'public.${spec.tableName} (${spec.idField.columnName}) on delete cascade,',
    )
    ..writeln(
      '  ${collaboration.userForeignKey} uuid not null references '
      'auth.users (id) on delete cascade,',
    )
    ..writeln('  $activeField boolean not null default true,')
    ..writeln(
      '  primary key (${collaboration.entityForeignKey}, '
      '${collaboration.userForeignKey})',
    )
    ..writeln(');')
    ..writeln(
      'alter table public.${collaboration.membershipTable} '
      'enable row level security;',
    )
    ..writeln()
    ..writeln(
      'create or replace function public.is_${spec.tableName}_owner(p_id uuid)',
    )
    ..writeln('returns boolean language sql stable security definer')
    ..writeln("set search_path = '' as \$\$")
    ..writeln(
      '  select exists (select 1 from public.${spec.tableName} entity '
      'where entity.${spec.idField.columnName} = p_id and '
      'entity.${spec.ownerField.columnName} = auth.uid());',
    )
    ..writeln('\$\$;')
    ..writeln(
      'drop policy if exists ${collaboration.membershipTable}_select on '
      'public.${collaboration.membershipTable};',
    )
    ..writeln(
      'drop policy if exists ${collaboration.membershipTable}_owner_insert on '
      'public.${collaboration.membershipTable};',
    )
    ..writeln(
      'drop policy if exists ${collaboration.membershipTable}_owner_update on '
      'public.${collaboration.membershipTable};',
    )
    ..writeln(
      'drop policy if exists ${collaboration.membershipTable}_owner_delete on '
      'public.${collaboration.membershipTable};',
    )
    ..writeln(
      'create or replace function public.is_${spec.tableName}_collaborator('
      'p_id uuid)',
    )
    ..writeln('returns boolean language sql stable security definer')
    ..writeln("set search_path = '' as \$\$")
    ..writeln(
      '  select exists (select 1 from public.${collaboration.membershipTable} '
      'member where member.${collaboration.entityForeignKey} = p_id and '
      'member.${collaboration.userForeignKey} = auth.uid() and '
      'member.$activeField);',
    )
    ..writeln('\$\$;')
    ..writeln(
      'revoke all on function public.is_${spec.tableName}_owner(uuid) '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'revoke all on function public.is_${spec.tableName}_collaborator(uuid) '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'grant execute on function public.is_${spec.tableName}_owner(uuid) '
      'to authenticated;',
    )
    ..writeln(
      'grant execute on function public.is_${spec.tableName}_collaborator(uuid) '
      'to authenticated;',
    )
    ..writeln(
      'create policy ${collaboration.membershipTable}_select on '
      'public.${collaboration.membershipTable} for select to authenticated '
      'using (${collaboration.userForeignKey} = (select auth.uid()) or '
      'public.is_${spec.tableName}_owner(${collaboration.entityForeignKey}));',
    )
    ..writeln(
      'create policy ${collaboration.membershipTable}_owner_insert on '
      'public.${collaboration.membershipTable} for insert to authenticated '
      'with check (public.is_${spec.tableName}_owner('
      '${collaboration.entityForeignKey}));',
    )
    ..writeln(
      'create policy ${collaboration.membershipTable}_owner_update on '
      'public.${collaboration.membershipTable} for update to authenticated '
      'using (public.is_${spec.tableName}_owner('
      '${collaboration.entityForeignKey})) with check '
      '(public.is_${spec.tableName}_owner('
      '${collaboration.entityForeignKey}));',
    )
    ..writeln(
      'create policy ${collaboration.membershipTable}_owner_delete on '
      'public.${collaboration.membershipTable} for delete to authenticated '
      'using (public.is_${spec.tableName}_owner('
      '${collaboration.entityForeignKey}));',
    )
    ..writeln(
      'revoke all on public.${collaboration.membershipTable} from anon;',
    );
  buffer
    ..writeln(
      'revoke all on public.${collaboration.membershipTable} '
      'from authenticated;',
    )
    ..writeln(
      'grant select on public.${collaboration.membershipTable} to authenticated;',
    );
  _emitParticipantFunction(buffer, spec);
}

void _emitParticipantFunction(StringBuffer buffer, EntitySpec spec) {
  final participantFields = spec.participantFields;
  if (participantFields.isEmpty) return;
  final predicate = participantFields
      .map((field) => 'entity.${field.columnName} = auth.uid()')
      .join(' or ');
  buffer
    ..writeln()
    ..writeln(
      'create or replace function public.is_${spec.tableName}_participant('
      'p_id uuid)',
    )
    ..writeln('returns boolean language sql stable security definer')
    ..writeln("set search_path = '' as \$\$")
    ..writeln(
      '  select exists (select 1 from public.${spec.tableName} entity '
      'where entity.${spec.idField.columnName} = p_id and '
      '($predicate));',
    )
    ..writeln('\$\$;')
    ..writeln(
      'revoke all on function public.is_${spec.tableName}_participant(uuid) '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'grant execute on function public.is_${spec.tableName}_participant(uuid) '
      'to authenticated;',
    );
}

void _emitAccessReferenceFunction(StringBuffer buffer, EntitySpec spec) {
  if (spec.accessReferenceFields.isEmpty) return;
  final access = _accessReferenceExpression(
    spec,
    idFor: (field) => 'entity.${field.columnName}',
  );
  final ownership = _ownershipReferenceExpression(
    spec,
    idFor: (field) => 'entity.${field.columnName}',
    rowOwner: 'entity.${spec.ownerField.columnName}',
  );
  final predicate = ownership == null ? access : '($access) and ($ownership)';
  buffer
    ..writeln()
    ..writeln(
      'create or replace function public.is_${spec.tableName}_reference('
      'p_id uuid)',
    )
    ..writeln('returns boolean language sql stable security definer')
    ..writeln("set search_path = '' as \$\$")
    ..writeln(
      '  select exists (select 1 from public.${spec.tableName} entity '
      'where entity.${spec.idField.columnName} = p_id and ($predicate));',
    )
    ..writeln('\$\$;')
    ..writeln(
      'revoke all on function public.is_${spec.tableName}_reference(uuid) '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'grant execute on function public.is_${spec.tableName}_reference(uuid) '
      'to authenticated;',
    );
}

void _emitRls(
  StringBuffer buffer,
  EntitySpec spec, {
  EntitySpec? activitySource,
}) {
  buffer
    ..writeln()
    ..writeln(
      'alter table public.${spec.tableName} enable row level security;',
    );

  if (activitySource != null) {
    final subject = '${spec.tableName}.subject_id';
    final owner = '${spec.tableName}.${spec.ownerField.columnName}';
    final actor = '${spec.tableName}.actor_id';
    final sourceReadAccess = _activitySourceAccessExpression(
      activitySource,
      subject,
      operations: const {RlsOperation.select},
    );
    final sourceWriteAccess = _activitySourceAccessExpression(
      activitySource,
      subject,
    );
    final sourceOwner =
        '(select source.${activitySource.ownerField.columnName} from '
        'public.${activitySource.tableName} source where '
        'source.${activitySource.idField.columnName} = $subject)';
    final selectPolicy = '${spec.tableName}_select_source';
    final insertPolicy = '${spec.tableName}_insert_source_operation';
    buffer
      ..writeln(
        'drop policy if exists $selectPolicy on public.${spec.tableName};',
      )
      ..writeln(
        'create policy $selectPolicy on public.${spec.tableName} for select '
        'to authenticated using (($owner = $sourceOwner) and '
        '($sourceReadAccess));',
      )
      ..writeln(
        'drop policy if exists $insertPolicy on public.${spec.tableName};',
      )
      ..writeln(
        'create policy $insertPolicy on public.${spec.tableName} for insert '
        'to authenticated with check (($actor = auth.uid()) and '
        '($owner = $sourceOwner) and ($sourceWriteAccess));',
      );
  } else {
    for (final grant in spec.security.grants.where(
      (grant) => grant.principal != RlsPrincipal.relationship,
    )) {
      final operation = grant.operation.name;
      final principal = _principalExpression(
        spec,
        grant.principal,
        operation: grant.operation,
      );
      final ownership = _ownershipReferenceExpression(
        spec,
        idFor: (field) => '${spec.tableName}.${field.columnName}',
        rowOwner: '${spec.tableName}.${spec.ownerField.columnName}',
      );
      final grantedExpression = ownership == null
          ? principal
          : '($principal) and ($ownership)';
      final expression = _guardRlsWithReferenceAccess(
        spec,
        grant.operation,
        grantedExpression,
      );
      final policyName =
          '${spec.tableName}_${operation}_${grant.principal.name}';
      buffer
        ..writeln(
          'drop policy if exists $policyName on public.${spec.tableName};',
        )
        ..write(
          'create policy $policyName on public.${spec.tableName} '
          'for $operation to authenticated',
        );
      switch (grant.operation) {
        case RlsOperation.select:
        case RlsOperation.delete:
          buffer.writeln(' using ($expression);');
        case RlsOperation.insert:
          buffer.writeln(' with check ($expression);');
        case RlsOperation.update:
          buffer.writeln(' using ($expression) with check ($expression);');
      }
    }
  }
  for (final operation in spec.relationshipAccessOperations) {
    final policyName = '${spec.tableName}_${operation.name}_relationship';
    final relationshipExpression =
        'public.is_${spec.tableName}_relationship_${operation.name}('
        '${spec.tableName}.${spec.idField.columnName})';
    final expression = _guardRlsWithReferenceAccess(
      spec,
      operation,
      relationshipExpression,
    );
    buffer
      ..writeln(
        'drop policy if exists $policyName on public.${spec.tableName};',
      )
      ..write(
        'create policy $policyName on public.${spec.tableName} '
        'for ${operation.name} to authenticated',
      );
    switch (operation) {
      case RlsOperation.select:
      case RlsOperation.delete:
        buffer.writeln(' using ($expression);');
      case RlsOperation.update:
        buffer.writeln(' using ($expression) with check ($expression);');
      case RlsOperation.insert:
        throw StateError('Relationship access cannot grant insert.');
    }
  }
  buffer
    ..writeln('revoke all on public.${spec.tableName} from anon;')
    ..writeln('revoke all on public.${spec.tableName} from authenticated;')
    ..writeln('grant select on public.${spec.tableName} to authenticated;');
}

String _activitySourceAccessExpression(
  EntitySpec source,
  String idExpression, {
  Set<RlsOperation> operations = const {
    RlsOperation.select,
    RlsOperation.update,
  },
}) {
  final expressions = source.security.grants
      .where((grant) => operations.contains(grant.operation))
      .map(
        (grant) => _principalByIdExpression(
          source,
          grant.principal,
          idExpression,
          operation: grant.operation,
        ),
      )
      .toSet();
  if (operations.contains(RlsOperation.select) &&
      source.relationshipAccessOperations.contains(RlsOperation.select)) {
    expressions.add(
      'public.is_${source.tableName}_relationship_select($idExpression)',
    );
  }
  return expressions.isEmpty ? 'false' : expressions.join(' or ');
}

String _guardRlsWithReferenceAccess(
  EntitySpec spec,
  RlsOperation operation,
  String grantedExpression,
) {
  if (!spec.security.guardsWithReferenceAccess(operation)) {
    return grantedExpression;
  }
  final access = _accessReferenceExpression(
    spec,
    idFor: (field) => '${spec.tableName}.${field.columnName}',
  );
  return '($grantedExpression) and ($access)';
}

String _postgresDeleteAction(ReferenceDeleteAction action) => switch (action) {
  ReferenceDeleteAction.restrict => 'restrict',
  ReferenceDeleteAction.cascade => 'cascade',
  ReferenceDeleteAction.setNull => 'set null',
};

String _principalExpression(
  EntitySpec spec,
  RlsPrincipal principal, {
  required RlsOperation operation,
}) {
  final ownerColumn = spec.ownerField.columnName;
  return switch (principal) {
    RlsPrincipal.owner => '(select auth.uid()) = $ownerColumn',
    RlsPrincipal.participant =>
      spec.participantFields
          .map((field) => '(select auth.uid()) = ${field.columnName}')
          .join(' or '),
    RlsPrincipal.authenticated => '(select auth.uid()) is not null',
    RlsPrincipal.collaborator =>
      operation == RlsOperation.select &&
              (spec.security.collaboration?.hasAdditionalReadableStates ??
                  false)
          ? _collaborationViewerExpression(spec)
          : _collaborationExpression(spec),
    RlsPrincipal.reference =>
      operation == RlsOperation.insert
          ? _referenceInsertExpression(
              spec,
              idFor: (field) => '${spec.tableName}.${field.columnName}',
            )
          : _accessReferenceExpression(
              spec,
              idFor: (field) => '${spec.tableName}.${field.columnName}',
            ),
    RlsPrincipal.relationship =>
      'public.is_${spec.tableName}_relationship_${operation.name}('
          '${spec.tableName}.${spec.idField.columnName})',
  };
}

String _referenceInsertExpression(
  EntitySpec spec, {
  required String Function(FieldSpec field) idFor,
}) {
  final access = spec.accessReferenceFields.isEmpty
      ? _ownershipReferenceAccessExpression(spec, idFor: idFor)
      : _accessReferenceExpression(spec, idFor: idFor);
  if (spec.participantFields.isEmpty) return access;
  final self = spec.participantFields
      .map((field) => 'auth.uid() = ${idFor(field)}')
      .join(' or ');
  return '($access) and (${spec.participantFields.length == 1 ? self : '($self)'})';
}

String _accessReferenceExpression(
  EntitySpec spec, {
  required String Function(FieldSpec field) idFor,
}) {
  return spec.accessReferenceGroups
      .map((group) {
        final expression = group
            .map((field) {
              final reference = field.reference!;
              final id = idFor(field);
              final allowed = _targetReadableByIdExpression(reference, id);
              return '($allowed)';
            })
            .join(' or ');
        return group.length == 1 ? expression : '($expression)';
      })
      .join(' and ');
}

String _ownershipReferenceAccessExpression(
  EntitySpec spec, {
  required String Function(FieldSpec field) idFor,
}) {
  final references = spec.ownershipReferenceFields;
  if (references.isEmpty) return 'false';
  final expression = references
      .map((field) {
        final id = idFor(field);
        final readable = _targetReadableByIdExpression(field.reference!, id);
        return field.nullable
            ? '($id is not null and ($readable))'
            : '($readable)';
      })
      .join(' or ');
  return references.length == 1 ? expression : '($expression)';
}

String _targetReadableByIdExpression(
  ReferenceSpec reference,
  String idExpression,
) {
  final expressions = reference.targetSelectPrincipals
      .map(
        (principal) =>
            _targetPrincipalByIdExpression(reference, principal, idExpression),
      )
      .toSet();
  if (reference.targetReadableByRelationship) {
    expressions.add(
      'public.is_${reference.targetTableName}_relationship_select('
      '$idExpression)',
    );
  }
  return expressions.join(' or ');
}

String? _ownershipReferenceExpression(
  EntitySpec spec, {
  required String Function(FieldSpec field) idFor,
  required String rowOwner,
}) {
  final ownershipReferences = spec.ownershipReferenceFields;
  if (ownershipReferences.isEmpty) return null;
  final alternatives = ownershipReferences
      .map((ownershipReference) {
        final reference = ownershipReference.reference!;
        final id = idFor(ownershipReference);
        final equality =
            '$rowOwner = '
            '(select target.${reference.ownershipSourceColumnName} from '
            'public.${reference.targetTableName} target where '
            'target.${EntityConventions.idColumnName} = $id)';
        return ownershipReference.nullable
            ? '($id is not null and $equality)'
            : '($equality)';
      })
      .join(' or ');
  return ownershipReferences.length == 1 ? alternatives : '($alternatives)';
}

String _targetPrincipalByIdExpression(
  ReferenceSpec reference,
  RlsPrincipal principal,
  String idExpression, {
  RlsOperation operation = RlsOperation.select,
}) => switch (principal) {
  RlsPrincipal.owner =>
    'public.is_${reference.targetTableName}_owner($idExpression)',
  RlsPrincipal.participant =>
    'public.is_${reference.targetTableName}_participant($idExpression)',
  RlsPrincipal.collaborator =>
    'public.is_${reference.targetTableName}_collaborator($idExpression)',
  RlsPrincipal.reference =>
    'public.is_${reference.targetTableName}_reference($idExpression)',
  RlsPrincipal.relationship =>
    'public.is_${reference.targetTableName}_relationship_${operation.name}('
        '$idExpression)',
  RlsPrincipal.authenticated =>
    'exists (select 1 from public.${reference.targetTableName} target '
        'where target.${EntityConventions.idColumnName} = $idExpression)',
};

String _collaborationExpression(EntitySpec spec) {
  final collaboration = spec.security.collaboration;
  if (collaboration == null) {
    throw StateError('A collaborator grant requires CollaborationAccess.');
  }
  return 'public.is_${spec.tableName}_collaborator('
      '${spec.tableName}.${spec.idField.columnName})';
}

String _collaborationViewerExpression(EntitySpec spec) {
  final collaboration = spec.security.collaboration;
  if (collaboration == null || !collaboration.hasAdditionalReadableStates) {
    throw StateError(
      'A workflow viewer expression requires additional readable states.',
    );
  }
  return 'public.is_${spec.tableName}_viewer('
      '${spec.tableName}.${spec.idField.columnName})';
}

String _rpcAuthorizationExpression(
  EntitySpec spec,
  RlsOperation operation,
  String idExpression,
) {
  final expressions = spec.security.grants
      .where((grant) => grant.operation == operation)
      .map(
        (grant) => _principalByIdExpression(
          spec,
          grant.principal,
          idExpression,
          operation: operation,
        ),
      )
      .toSet();
  if (spec.relationshipAccessOperations.contains(operation)) {
    expressions.add(
      'public.is_${spec.tableName}_relationship_${operation.name}('
      '$idExpression)',
    );
  }
  final grants = expressions.isEmpty ? 'false' : expressions.join(' or ');
  if (!spec.security.guardsWithReferenceAccess(operation)) return grants;
  return '($grants) and '
      'public.is_${spec.tableName}_reference($idExpression)';
}

String _createAuthorizationExpression(
  EntitySpec spec,
  String patchExpression, {
  EntitySpec? activitySource,
}) {
  if (activitySource != null) {
    final subject = "($patchExpression ->> 'subjectId')::uuid";
    final owner = "($patchExpression ->> '${spec.ownerField.name}')::uuid";
    final actor = "($patchExpression ->> 'actorId')::uuid";
    final sourceOperation = "($patchExpression ->> 'sourceOperationId')::uuid";
    final sourceOwner =
        '(select source.${activitySource.ownerField.columnName} from '
        'public.${activitySource.tableName} source where '
        'source.${activitySource.idField.columnName} = $subject)';
    final provesSourceOperation =
        'exists (select 1 from public.local_entity_operation_receipts '
        'source_receipt '
        "where source_receipt.entity_type = '${activitySource.className}' "
        'and source_receipt.entity_id = $subject '
        'and source_receipt.user_id = $actor '
        'and source_receipt.operation_id = $sourceOperation)';
    return '($actor = auth.uid()) and ($owner = $sourceOwner) and '
        '($provesSourceOperation)';
  }
  final expressions = spec.security.grants
      .where((grant) => grant.operation == RlsOperation.insert)
      .map(
        (grant) => switch (grant.principal) {
          RlsPrincipal.owner =>
            "($patchExpression ->> '${spec.ownerField.name}')::uuid = auth.uid()",
          RlsPrincipal.participant => 'false',
          RlsPrincipal.authenticated => 'auth.uid() is not null',
          RlsPrincipal.collaborator => 'false',
          RlsPrincipal.relationship => 'false',
          RlsPrincipal.reference => _referenceInsertExpression(
            spec,
            idFor: (field) => "($patchExpression ->> '${field.name}')::uuid",
          ),
        },
      )
      .toSet();
  final grants = expressions.isEmpty ? 'false' : expressions.join(' or ');
  final ownership = _ownershipReferenceExpression(
    spec,
    idFor: (field) => "($patchExpression ->> '${field.name}')::uuid",
    rowOwner: "($patchExpression ->> '${spec.ownerField.name}')::uuid",
  );
  return ownership == null ? grants : '($grants) and ($ownership)';
}

String _patchKeyValidation(
  EntitySpec spec,
  Iterable<FieldSpec> mutable,
  Set<FieldSpec> commandFields,
) {
  String array(Iterable<FieldSpec> fields) {
    final names = fields.map((field) => "'${field.name}'").join(', ');
    return names.isEmpty ? 'array[]::text[]' : 'array[$names]::text[]';
  }

  final patchFields = array(mutable);
  final deleteFields = array(commandFields);
  final sections = <String>[];
  if (spec.canUpdate) {
    sections.add('''
  if p_operation = 'patch' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any($patchFields))
  ) then
    raise exception 'Patch contains a forbidden field' using errcode = '22023';
  end if;''');
  }
  if (spec.canDelete) {
    sections.add(
      '''
  if p_operation = 'delete' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any($deleteFields))
  ) then
    raise exception 'Delete contains a forbidden field' using errcode = '22023';
  end if;
  ${commandFields.isEmpty ? '' : "if p_operation = 'delete' and (select count(*) from jsonb_object_keys(p_patch)) <> 1 then\n    raise exception 'Delete requires exactly one command field' using errcode = '22023';\n  end if;"}''',
    );
  }
  return sections.join('\n');
}

String _orderScopePatchExpression(EntitySpec spec) {
  final fields = spec.orderScopeFields;
  if (fields.isEmpty) return "'root'";
  if (!spec.usesEncodedOrderScopeKey) {
    return "current_operation -> 'patch' ->> '${fields.single.name}'";
  }
  return 'jsonb_build_array(${fields.map((field) => "current_operation -> 'patch' -> '${field.name}'").join(', ')})::text';
}

String _orderScopeRowExpression(EntitySpec spec, String? alias) {
  final fields = spec.orderScopeFields;
  if (fields.isEmpty) return "'root'";
  final prefix = alias == null ? '' : '$alias.';
  if (!spec.usesEncodedOrderScopeKey) {
    return '$prefix${fields.single.columnName}::text';
  }
  return 'jsonb_build_array(${fields.map((field) => '$prefix${field.columnName}').join(', ')})::text';
}

String _orderScopeRowJsonExpression(EntitySpec spec, String alias) {
  final fields = spec.orderScopeFields;
  if (fields.isEmpty) return "'{}'::jsonb";
  return 'jsonb_build_object(${fields.map((field) => "'${field.name}', $alias.${field.columnName}").join(', ')})';
}

String _orderScopeRowsMatch(
  EntitySpec spec, {
  required String left,
  required String right,
}) => spec.orderScopeFields
    .map(
      (field) =>
          '$left.${field.columnName} is not distinct from '
          '$right.${field.columnName}',
    )
    .join(' and ');

String _orderScopeRowMatchesCreatePatch(EntitySpec spec, String alias) => spec
    .orderScopeFields
    .map(
      (field) =>
          '$alias.${field.columnName} is not distinct from '
          '(${_jsonCast("current_operation -> 'patch' -> '${field.name}'", field)})',
    )
    .join(' and ');

String _orderScopeTransferKeyExpression(EntitySpec spec) {
  final transferNames = spec.orderScopeTransferFields
      .map((field) => field.name)
      .toSet();
  return 'jsonb_build_array(${spec.orderScopeFields.map((field) => transferNames.contains(field.name) ? "current_operation -> 'patch' -> 'targetScope' -> '${field.name}'" : 'canonical.${field.columnName}').join(', ')})::text';
}

String _orderScopeTransferJsonExpression(EntitySpec spec) {
  final transferNames = spec.orderScopeTransferFields
      .map((field) => field.name)
      .toSet();
  return 'jsonb_build_object(${spec.orderScopeFields.map((field) => "'${field.name}', ${transferNames.contains(field.name) ? _jsonCast("current_operation -> 'patch' -> 'targetScope' -> '${field.name}'", field) : 'canonical.${field.columnName}'}").join(', ')})';
}

String _orderHierarchyPartitionLockExpression(EntitySpec spec) {
  final transferNames = spec.orderScopeTransferFields
      .map((field) => field.name)
      .toSet();
  final fixedPartitionFields = spec.orderScopeFields
      .where((field) => !transferNames.contains(field.name))
      .toList(growable: false);
  if (fixedPartitionFields.isEmpty) {
    return "'${spec.className}:hierarchy'";
  }
  final values = fixedPartitionFields
      .map((field) => 'canonical.${field.columnName}')
      .join(', ');
  return "'${spec.className}:hierarchy:' || "
      'jsonb_build_array($values)::text';
}

String _orderScopeRowMatchesTransferTarget(EntitySpec spec, String alias) {
  final transferNames = spec.orderScopeTransferFields
      .map((field) => field.name)
      .toSet();
  return spec.orderScopeFields
      .map(
        (field) =>
            '$alias.${field.columnName} is not distinct from '
            '${transferNames.contains(field.name) ? '(${_jsonCast("current_operation -> 'patch' -> 'targetScope' -> '${field.name}'", field)})' : 'canonical.${field.columnName}'}',
      )
      .join(' and ');
}

String _orderTransferJsonTypeCheck(FieldSpec field) {
  final type = switch (field.sqlType) {
    SqlType.boolean => 'boolean',
    SqlType.integer || SqlType.real => 'number',
    SqlType.text ||
    SqlType.uuid ||
    SqlType.date ||
    SqlType.timestampWithTimeZone => 'string',
  };
  final expression =
      "current_operation -> 'patch' -> 'targetScope' -> '${field.name}'";
  return field.nullable
      ? "jsonb_typeof($expression) not in ('$type', 'null')"
      : "jsonb_typeof($expression) <> '$type'";
}

String _pushOperationRoutingSql(
  EntitySpec spec, {
  EntitySpec? activitySource,
  required String createColumns,
  required String createValues,
  required String createFieldNames,
  required String createRequiredFieldNames,
}) {
  final createOrderScopeKey = !spec.hasOrderedCapability
      ? ''
      : _orderScopePatchExpression(spec);
  final storedOrderScopeKey = !spec.hasOrderedCapability
      ? ''
      : _orderScopeRowExpression(spec, 'candidate');
  final createOrderScopeLock = !spec.hasOrderedCapability
      ? ''
      : '''      order_scope_key := $createOrderScopeKey;
      perform pg_advisory_xact_lock(
        hashtextextended('${spec.className}:' || order_scope_key, 0)
      );
      insert into public.local_entity_order_scopes (entity_type, scope_key)
      values ('${spec.className}', order_scope_key)
      on conflict (entity_type, scope_key) do nothing;''';
  final createOrderScopeAdvance = !spec.hasOrderedCapability
      ? ''
      : '''      update public.local_entity_order_scopes
      set version = version + 1
      where entity_type = '${spec.className}' and scope_key = order_scope_key
      returning version into current_order_scope_version;''';
  final createOrderedIntent = !spec.hasOrderedCapability
      ? ''
      : _orderedCreateIntentSql(spec);
  final orderedMembershipPrelude =
      !spec.hasOrderedCapability || !spec.hasStateMutations
      ? ''
      : '''      if current_operation -> 'patch' ?| array[${spec.orderMembershipConditions.map((condition) => "'${condition.$1.name}'").join(', ')}] then
        if current_operation ->> 'operation' = 'delete'
           and not (${_rpcAuthorizationExpression(spec, RlsOperation.delete, "(current_operation ->> 'entityId')::uuid")}) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        if current_operation ->> 'operation' = 'patch'
           and not (${_rpcAuthorizationExpression(spec, RlsOperation.update, "(current_operation ->> 'entityId')::uuid")}) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        select $storedOrderScopeKey,
               (${_orderMembershipSql(spec, 'candidate')}) <>
                 (${_orderMembershipPatchSql(spec, 'candidate')})
        into order_scope_key, order_scope_membership_changed
        from public.${spec.tableName} candidate
        where candidate.${spec.idField.columnName} =
          (current_operation ->> 'entityId')::uuid;
        if not found then
          raise exception 'Entity not found' using errcode = 'P0002';
        end if;
        if order_scope_membership_changed then
          perform pg_advisory_xact_lock(
            hashtextextended('${spec.className}:' || order_scope_key, 0)
          );
          insert into public.local_entity_order_scopes (entity_type, scope_key)
          values ('${spec.className}', order_scope_key)
          on conflict (entity_type, scope_key) do nothing;
          select scope.version into current_order_scope_version
          from public.local_entity_order_scopes scope
          where scope.entity_type = '${spec.className}'
            and scope.scope_key = order_scope_key
          for update;
        end if;
      end if;''';
  final orderedMembershipAdvance =
      !spec.hasOrderedCapability || !spec.hasStateMutations
      ? ''
      : '''      if order_scope_membership_changed then
        update public.local_entity_order_scopes
        set version = version + 1
        where entity_type = '${spec.className}' and scope_key = order_scope_key
        returning version into current_order_scope_version;
      end if;''';
  final branches = <(String, String)>[];
  if (spec.canCreate) {
    branches.add((
      "current_operation ->> 'operation' = 'create'",
      '''      if exists (select 1 from jsonb_object_keys(current_operation -> 'patch') key
          where not (key = any(array[$createFieldNames]::text[])))
          or not ((current_operation -> 'patch') ?& array[$createRequiredFieldNames])${spec.hasOrderedCapability ? "\n          or (not (current_operation ? 'orderedCreate') and not ((current_operation -> 'patch') ? '${spec.orderRankField!.name}'))" : ''} then
        raise exception 'Create contains missing or forbidden fields' using errcode = '22023';
      end if;
      if (current_operation -> 'patch' ->> '${spec.idField.name}')::uuid
          <> (current_operation ->> 'entityId')::uuid then
        raise exception 'Create entity ID mismatch' using errcode = '22023';
      end if;
      if not (${_createAuthorizationExpression(spec, "current_operation -> 'patch'", activitySource: activitySource)}) then
        raise exception 'Create access denied' using errcode = '42501';
      end if;
${!spec.hasOwnershipReference && activitySource == null ? "      if (current_operation -> 'patch' ->> '${spec.ownerField.name}')::uuid\n          <> auth.uid() then\n        raise exception 'Owner must match authenticated user' using errcode = '42501';\n      end if;" : ''}
${[_initialStateValidationSql(spec, "current_operation -> 'patch'", indent: '      '), _actionInitialStateValidationSql(spec, "current_operation -> 'patch'", indent: '      '), _referenceValidation(spec, "current_operation -> 'patch'", indent: '      '), _workflowMembershipCreateValidationSql(spec, "current_operation -> 'patch'", indent: '      ')].where((section) => section.isNotEmpty).join('\n')}${createOrderScopeLock.isEmpty ? '' : '\n$createOrderScopeLock'}${createOrderedIntent.isEmpty ? '' : '\n$createOrderedIntent'}
      insert into public.${spec.tableName} ($createColumns)
      values ($createValues) returning * into canonical;${createOrderScopeAdvance.isEmpty ? '' : '\n$createOrderScopeAdvance'}''',
    ));
  }
  if (spec.canCommand) {
    branches.add((
      "current_operation ->> 'operation' = 'command'",
      _semanticCommandSql(spec),
    ));
  }
  if (spec.hasStateMutations) {
    final operations = [
      if (spec.canUpdate) "'patch'",
      if (spec.canDelete) "'delete'",
    ].join(', ');
    branches.add((
      "current_operation ->> 'operation' in ($operations)",
      '''${orderedMembershipPrelude.isEmpty ? '' : '$orderedMembershipPrelude\n'}      canonical := public.apply_${spec.tableName}_patch(
        (current_operation ->> 'entityId')::uuid,
        (current_operation ->> 'baseServerVersion')::bigint,
        current_operation ->> 'operation',
        current_operation -> 'patch');${orderedMembershipAdvance.isEmpty ? '' : '\n$orderedMembershipAdvance'}''',
    ));
  }
  if (branches.isEmpty) {
    throw StateError(
      '${spec.className} has no client operations and does not need a push RPC.',
    );
  }

  final buffer = StringBuffer();
  for (final (index, branch) in branches.indexed) {
    buffer
      ..writeln("    ${index == 0 ? 'if' : 'elsif'} ${branch.$1} then")
      ..writeln(branch.$2);
  }
  buffer.writeln('    end if;');
  return buffer.toString().trimRight();
}

String _collaborationPublicationSql(EntitySpec spec) {
  final collaboration = spec.security.collaboration;
  if (collaboration == null || !collaboration.isDirect) return '';
  return '''
do \$\$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = '${collaboration.membershipTable}'
     ) then
    alter publication supabase_realtime add table public.${collaboration.membershipTable};
  end if;
end;
\$\$;''';
}

String _collaborationCommandSql(EntitySpec spec) {
  final collaboration = spec.security.collaboration;
  if (collaboration == null || !collaboration.isDirect) {
    return "      raise exception 'Entity has no collaboration commands' using errcode = '22023';";
  }
  final ownerColumn = spec.ownerField.columnName;
  final activeColumn = collaboration.activeField!;
  return '''
      if current_operation ->> 'commandName' <> 'setCollaborator' then
        raise exception 'Unsupported command' using errcode = '22023';
      end if;
      if exists (
        select 1 from jsonb_object_keys(current_operation -> 'patch') key
        where not (key = any(array['userId', 'active']::text[]))
      ) or not ((current_operation -> 'patch') ?& array['userId', 'active']) then
        raise exception 'Collaboration command has invalid fields' using errcode = '22023';
      end if;
      if jsonb_typeof(current_operation -> 'patch' -> 'userId') <> 'string'
         or jsonb_typeof(current_operation -> 'patch' -> 'active') <> 'boolean' then
        raise exception 'Collaboration command has invalid field types' using errcode = '22023';
      end if;
      if not public.is_${spec.tableName}_owner(
        (current_operation ->> 'entityId')::uuid
      ) then
        raise exception 'Only the owner can manage collaborators' using errcode = '42501';
      end if;
      select * into canonical from public.${spec.tableName}
      where ${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
      for update;
      if not found then
        raise exception 'Entity not found' using errcode = 'P0002';
      end if;
      if (current_operation -> 'patch' ->> 'userId')::uuid = canonical.$ownerColumn then
        raise exception 'Owner cannot be added as collaborator' using errcode = '22023';
      end if;
      insert into public.${collaboration.membershipTable} (
        ${collaboration.entityForeignKey},
        ${collaboration.userForeignKey},
        $activeColumn
      ) values (
        canonical.${spec.idField.columnName},
        (current_operation -> 'patch' ->> 'userId')::uuid,
        (current_operation -> 'patch' ->> 'active')::boolean
      )
      on conflict (${collaboration.entityForeignKey}, ${collaboration.userForeignKey})
      do update set $activeColumn = excluded.$activeColumn;
      delete from public.local_entity_changes
      where entity_type = '${spec.className}'
        and entity_id = canonical.${spec.idField.columnName}
        and audience_user_id = (current_operation -> 'patch' ->> 'userId')::uuid;
      insert into public.local_entity_changes (
        entity_type,
        entity_id,
        owner_id,
        server_version,
        operation_id,
        audience_user_id,
        is_revocation,
        record
      ) values (
        '${spec.className}',
        canonical.${spec.idField.columnName},
        canonical.$ownerColumn,
        canonical.${spec.serverVersionField.columnName},
        operation_uuid,
        (current_operation -> 'patch' ->> 'userId')::uuid,
        not (current_operation -> 'patch' ->> 'active')::boolean,
        to_jsonb(canonical)
      );''';
}

String _orderedCreateIntentSql(EntitySpec spec) {
  final rank = spec.orderRankField!;
  final memberScopeCheck = spec.hasRootOrderScope
      ? ''
      : ' and ${_orderScopeRowMatchesCreatePatch(spec, 'member')}';
  final maximum = GeneratedOrderRanks.upperBoundaryValue;
  final indexedRecovery = _orderedIndexedWindowRecoverySql(
    spec,
    placementExpression: "current_operation -> 'orderedCreate' ->> 'placement'",
    memberScopeCheck: memberScopeCheck,
    excludeEntity: false,
    supportsAnchor: false,
    maximum: maximum,
  );
  final boundedRecovery =
      '''
          with ordered_scope as (
            select
              member.${spec.idField.columnName} as member_id,
              row_number() over (
                order by member.${rank.columnName},
                         member.${spec.idField.columnName}
              ) as position,
              count(*) over () as scope_size
            from public.${spec.tableName} member
            where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
          ), rebalanced as (
            select
              member_id,
              trunc(
                ($maximum::numeric * position::numeric) /
                (scope_size::numeric + 1)
              ) as next_rank
            from ordered_scope
          )
          update public.${spec.tableName} member
          set ${rank.columnName} = lpad(rebalanced.next_rank::text, 78, '0'),
              ${spec.serverVersionField.columnName} =
                member.${spec.serverVersionField.columnName} + 1
          from rebalanced
          where member.${spec.idField.columnName} = rebalanced.member_id;
          if current_operation -> 'orderedCreate' ->> 'placement' = 'first' then
            lower_order_rank := 0;
            select member.${rank.columnName}::numeric into upper_order_rank
            from public.${spec.tableName} member
            where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
            order by member.${rank.columnName}, member.${spec.idField.columnName}
            limit 1;
          else
            upper_order_rank := $maximum::numeric;
            select member.${rank.columnName}::numeric into lower_order_rank
            from public.${spec.tableName} member
            where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
            order by member.${rank.columnName} desc,
                     member.${spec.idField.columnName} desc
            limit 1;
          end if;
          next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
          if next_order_rank <= lower_order_rank
             or next_order_rank >= upper_order_rank then
            raise exception 'Ordered scope rank rebalance failed'
              using errcode = 'P0001';
          end if;''';
  final recovery = spec.cardinality == Cardinality.unbounded
      ? _indentSql(indexedRecovery, 10)
      : boundedRecovery;
  return '''      if current_operation ? 'orderedCreate' then
        if jsonb_typeof(current_operation -> 'orderedCreate') <> 'object' then
          raise exception 'Ordered create intent must be an object'
            using errcode = '22023';
        end if;
        if exists (
          select 1
          from jsonb_object_keys(current_operation -> 'orderedCreate') key
          where not (key = any(array['placement', 'scopeBaseVersion']::text[]))
        ) or not ((current_operation -> 'orderedCreate') ?&
            array['placement', 'scopeBaseVersion']) then
          raise exception 'Ordered create intent has invalid fields'
            using errcode = '22023';
        end if;
        if jsonb_typeof(current_operation -> 'orderedCreate' -> 'placement') <>
              'string'
           or current_operation -> 'orderedCreate' ->> 'placement'
              not in ('first', 'last')
           or jsonb_typeof(
                current_operation -> 'orderedCreate' -> 'scopeBaseVersion'
              ) <> 'number'
           or (current_operation -> 'orderedCreate' ->>
                'scopeBaseVersion')::bigint < 0 then
          raise exception 'Ordered create intent has invalid field types'
            using errcode = '22023';
        end if;
        select scope.version into current_order_scope_version
        from public.local_entity_order_scopes scope
        where scope.entity_type = '${spec.className}'
          and scope.scope_key = order_scope_key
        for update;
        if (current_operation -> 'orderedCreate' ->>
              'scopeBaseVersion')::bigint > current_order_scope_version then
          raise exception 'Ordered scope base version is ahead of the server'
            using errcode = '22023';
        end if;
        if current_operation -> 'orderedCreate' ->> 'placement' = 'first' then
          lower_order_rank := 0;
          select member.${rank.columnName}::numeric into upper_order_rank
          from public.${spec.tableName} member
          where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
          order by member.${rank.columnName}, member.${spec.idField.columnName}
          limit 1;
          if not found then
            upper_order_rank := $maximum::numeric;
          end if;
        else
          upper_order_rank := $maximum::numeric;
          select member.${rank.columnName}::numeric into lower_order_rank
          from public.${spec.tableName} member
          where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
          order by member.${rank.columnName} desc,
                   member.${spec.idField.columnName} desc
          limit 1;
          if not found then
            lower_order_rank := 0;
          end if;
        end if;
        next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
        if next_order_rank <= lower_order_rank
           or next_order_rank >= upper_order_rank then
$recovery
        end if;
        current_operation := jsonb_set(
          current_operation,
          '{patch,${rank.name}}',
          to_jsonb(lpad(next_order_rank::text, 78, '0')),
          true
        );
      end if;''';
}

String _orderMembershipSql(EntitySpec spec, [String? alias]) => [
  for (final (field, value) in spec.orderMembershipConditions)
    _orderMembershipFieldSql(field, value, alias),
].join(' and ');

String _orderMembershipPatchSql(EntitySpec spec, String alias) => [
  for (final (field, value) in spec.orderMembershipConditions)
    '''case
      when current_operation -> 'patch' ? '${field.name}' then
        ${_orderMembershipPatchValueSql(field, value)}
      else ${_orderMembershipFieldSql(field, value, alias)}
    end''',
].join(' and ');

String _orderMembershipFieldSql(FieldSpec field, Object? value, String? alias) {
  final column = '${alias == null ? '' : '$alias.'}${field.columnName}';
  return switch (value) {
    null => '$column is null',
    true => '$column is true',
    false => '$column is false',
    _ => throw StateError(
      'Ordered membership currently supports null and boolean conditions.',
    ),
  };
}

String _orderMembershipPatchValueSql(FieldSpec field, Object? value) {
  final patch = "current_operation -> 'patch' -> '${field.name}'";
  return switch (value) {
    null => "$patch = 'null'::jsonb",
    true => "$patch = 'true'::jsonb",
    false => "$patch = 'false'::jsonb",
    _ => throw StateError(
      'Ordered membership currently supports null and boolean conditions.',
    ),
  };
}

String _orderedIndexedWindowRecoverySql(
  EntitySpec spec, {
  required String placementExpression,
  required String memberScopeCheck,
  required bool excludeEntity,
  required bool supportsAnchor,
  required String maximum,
}) {
  final rank = spec.orderRankField!;
  final excluded = excludeEntity
      ? '''
      and member.${spec.idField.columnName} <>
          (current_operation ->> 'entityId')::uuid'''
      : '';
  final rightAnchor = !supportsAnchor
      ? ''
      : '''
      and ($placementExpression <> 'before' or
        (member.${rank.columnName}, member.${spec.idField.columnName}) >=
        (lpad(anchor_order_rank::text, 78, '0'),
         (current_operation -> 'patch' ->> 'anchorId')::uuid))''';
  final leftAnchor = !supportsAnchor
      ? ''
      : '''
      and ($placementExpression <> 'after' or
        (member.${rank.columnName}, member.${spec.idField.columnName}) <=
        (lpad(anchor_order_rank::text, 78, '0'),
         (current_operation -> 'patch' ->> 'anchorId')::uuid))''';
  return '''rebalance_window_size := 8;
loop
  if $placementExpression in ('first', 'before') then
    with limited as materialized (
      select member.${spec.idField.columnName} as member_id,
             member.${rank.columnName}::numeric as member_rank
      from public.${spec.tableName} member
      where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck$excluded$rightAnchor
      order by member.${rank.columnName}, member.${spec.idField.columnName}
      limit rebalance_window_size + 1
    ), candidates as (
      select limited.*,
             row_number() over (order by member_rank, member_id) as position
      from limited
    )
    select
      coalesce(
        array_agg(member_id order by position)
          filter (where position <= rebalance_window_size),
        '{}'::uuid[]
      ),
      max(member_rank) filter (where position = rebalance_window_size + 1),
      bool_or(position = rebalance_window_size + 1)
    into rebalance_member_ids, rebalance_outside_rank,
         rebalance_has_outside
    from candidates;
    rebalance_upper_rank := coalesce(
      rebalance_outside_rank,
      $maximum::numeric
    );
    rebalance_lower_rank := lower_order_rank;
  else
    with limited as materialized (
      select member.${spec.idField.columnName} as member_id,
             member.${rank.columnName}::numeric as member_rank
      from public.${spec.tableName} member
      where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck$excluded$leftAnchor
      order by member.${rank.columnName} desc,
               member.${spec.idField.columnName} desc
      limit rebalance_window_size + 1
    ), candidates as (
      select limited.*,
             row_number() over (order by member_rank desc, member_id desc)
               as position
      from limited
    )
    select
      coalesce(
        array_agg(member_id order by position desc)
          filter (where position <= rebalance_window_size),
        '{}'::uuid[]
      ),
      max(member_rank) filter (where position = rebalance_window_size + 1),
      bool_or(position = rebalance_window_size + 1)
    into rebalance_member_ids, rebalance_outside_rank,
         rebalance_has_outside
    from candidates;
    rebalance_lower_rank := coalesce(rebalance_outside_rank, 0);
    rebalance_upper_rank := upper_order_rank;
  end if;
  rebalance_member_count := coalesce(cardinality(rebalance_member_ids), 0);
  rebalance_step := trunc(
    (rebalance_upper_rank - rebalance_lower_rank) /
    (rebalance_member_count + 2)::numeric
  );
  if rebalance_step > 0 then
    with positioned as (
      select member_id, ordinality::numeric as position
      from unnest(rebalance_member_ids) with ordinality
    )
    update public.${spec.tableName} member
    set ${rank.columnName} = lpad((
          rebalance_lower_rank + rebalance_step *
          (positioned.position + case
            when $placementExpression in ('first', 'before') then 1
            else 0
          end)
        )::text, 78, '0'),
        ${spec.serverVersionField.columnName} =
          member.${spec.serverVersionField.columnName} + 1
    from positioned
    where member.${spec.idField.columnName} = positioned.member_id;
    next_order_rank := rebalance_lower_rank + rebalance_step *
      case
        when $placementExpression in ('first', 'before') then 1
        else rebalance_member_count + 1
      end;
    exit;
  end if;
  if not coalesce(rebalance_has_outside, false) then
    raise exception 'Ordered indexed rank window cannot be allocated'
      using errcode = 'P0001';
  end if;
  if rebalance_window_size > 1073741823 then
    raise exception 'Ordered indexed rank window exceeds supported size'
      using errcode = 'P0001';
  end if;
  rebalance_window_size := rebalance_window_size * 2;
end loop;''';
}

String _semanticCommandSql(EntitySpec spec) {
  if (spec.canCollaborate && !spec.hasOrderedCapability) {
    return _collaborationCommandSql(spec);
  }
  final branches = <String>[];
  if (spec.canCollaborate) {
    branches.add(
      "if current_operation ->> 'commandName' = 'setCollaborator' then\n"
      '${_indentSql(_collaborationCommandSql(spec), 2)}',
    );
  }
  if (spec.hasOrderedCapability) {
    branches.add(
      "${branches.isEmpty ? 'if' : 'elsif'} current_operation ->> "
      "'commandName' = 'moveInOrder' then\n"
      '${_indentSql(_orderedMoveCommandSql(spec), 2)}',
    );
    if (spec.orderScopeTransferAction != null) {
      branches.add(
        "elsif current_operation ->> 'commandName' = 'transferInOrder' then\n"
        '${_indentSql(_orderedTransferCommandSql(spec), 2)}',
      );
    }
    if (spec.cardinality == Cardinality.bounded) {
      branches.add(
        "elsif current_operation ->> 'commandName' = 'reorder' then\n"
        '${_indentSql(_orderedReorderCommandSql(spec), 2)}',
      );
    }
  }
  if (branches.isEmpty) {
    return "      raise exception 'Entity has no semantic commands' using errcode = '22023';";
  }
  return '''
      ${branches.join('\n      ')}
      else
        raise exception 'Unsupported command' using errcode = '22023';
      end if;''';
}

String _orderedTransferCommandSql(EntitySpec spec) {
  final rank = spec.orderRankField!;
  final targetFields = spec.orderScopeTransferFields;
  final targetNames = targetFields.map((field) => "'${field.name}'").join(', ');
  final typeChecks = targetFields
      .map(_orderTransferJsonTypeCheck)
      .join('\n   or ');
  final sourceKey = _orderScopeRowExpression(spec, 'canonical');
  final lockedSourceKey = _orderScopeRowExpression(spec, 'candidate');
  final targetKey = _orderScopeTransferKeyExpression(spec);
  final targetScope = _orderScopeTransferJsonExpression(spec);
  final targetMemberCheck = _orderScopeRowMatchesTransferTarget(spec, 'member');
  final targetMemberScopeCheck = ' and $targetMemberCheck';
  final targetAssignments = targetFields
      .map(
        (field) =>
            '${field.columnName} = ${_jsonCast("current_operation -> 'patch' -> 'targetScope' -> '${field.name}'", field)}',
      )
      .join(',\n    ');
  final recursiveField = targetFields
      .where((field) => field.reference?.targetClassName == spec.className)
      .firstOrNull;
  final hierarchyPartitionLock = recursiveField == null
      ? ''
      : '''
perform pg_advisory_xact_lock(
  hashtextextended(${_orderHierarchyPartitionLockExpression(spec)}, 0)
);''';
  final cycleValidation = recursiveField == null
      ? ''
      : '''
if current_operation -> 'patch' -> 'targetScope' -> '${recursiveField.name}' <> 'null'::jsonb
   and exists (
     with recursive ancestors(entity_id, parent_id) as (
       select candidate.${spec.idField.columnName}, candidate.${recursiveField.columnName}
       from public.${spec.tableName} candidate
       where candidate.${spec.idField.columnName} =
         (current_operation -> 'patch' -> 'targetScope' ->> '${recursiveField.name}')::uuid
       union
       select parent.${spec.idField.columnName}, parent.${recursiveField.columnName}
       from public.${spec.tableName} parent
       join ancestors child
         on parent.${spec.idField.columnName} = child.parent_id
     )
     select 1 from ancestors
     where entity_id = (current_operation ->> 'entityId')::uuid
   ) then
  raise exception 'Ordered hierarchy transfer would create a cycle'
    using errcode = '23514';
end if;''';
  final referenceValidation = _referenceValidation(
    spec,
    "current_operation -> 'patch' -> 'targetScope'",
    indent: '',
  );
  final maximum = GeneratedOrderRanks.upperBoundaryValue;
  final indexedRecovery = _orderedIndexedWindowRecoverySql(
    spec,
    placementExpression: "current_operation -> 'patch' ->> 'placement'",
    memberScopeCheck: targetMemberScopeCheck,
    excludeEntity: true,
    supportsAnchor: false,
    maximum: maximum,
  );
  final boundedRecovery =
      '''with ordered_scope as (
    select
      member.${spec.idField.columnName} as member_id,
      row_number() over (
        order by member.${rank.columnName}, member.${spec.idField.columnName}
      ) as position,
      count(*) over () as scope_size
    from public.${spec.tableName} member
    where ${_orderMembershipSql(spec, 'member')}
      and $targetMemberCheck
  ), rebalanced as (
    select
      member_id,
      trunc(($maximum::numeric * position::numeric) /
        (scope_size::numeric + 1)) as next_rank
    from ordered_scope
  )
  update public.${spec.tableName} member
  set ${rank.columnName} = lpad(rebalanced.next_rank::text, 78, '0'),
      ${spec.serverVersionField.columnName} = member.${spec.serverVersionField.columnName} + 1
  from rebalanced
  where member.${spec.idField.columnName} = rebalanced.member_id;
  if current_operation -> 'patch' ->> 'placement' = 'first' then
    lower_order_rank := 0;
    select member.${rank.columnName}::numeric into upper_order_rank
    from public.${spec.tableName} member
    where ${_orderMembershipSql(spec, 'member')}
      and $targetMemberCheck
    order by member.${rank.columnName}, member.${spec.idField.columnName}
    limit 1;
  else
    upper_order_rank := $maximum::numeric;
    select member.${rank.columnName}::numeric into lower_order_rank
    from public.${spec.tableName} member
    where ${_orderMembershipSql(spec, 'member')}
      and $targetMemberCheck
    order by member.${rank.columnName} desc, member.${spec.idField.columnName} desc
    limit 1;
  end if;
  next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
  if next_order_rank <= lower_order_rank or next_order_rank >= upper_order_rank then
    raise exception 'Ordered target scope rank rebalance failed'
      using errcode = 'P0001';
  end if;''';
  final recovery = spec.cardinality == Cardinality.unbounded
      ? indexedRecovery
      : boundedRecovery;
  return '''
if exists (
  select 1 from jsonb_object_keys(current_operation -> 'patch') key
  where not (key = any(array['targetScope', 'placement', 'sourceScopeBaseVersion', 'targetScopeBaseVersion']::text[]))
) or not ((current_operation -> 'patch') ?&
    array['targetScope', 'placement', 'sourceScopeBaseVersion', 'targetScopeBaseVersion']) then
  raise exception 'Ordered transfer has invalid fields' using errcode = '22023';
end if;
if jsonb_typeof(current_operation -> 'patch' -> 'targetScope') <> 'object'
   or jsonb_typeof(current_operation -> 'patch' -> 'placement') <> 'string'
   or current_operation -> 'patch' ->> 'placement' not in ('first', 'last')
   or jsonb_typeof(current_operation -> 'patch' -> 'sourceScopeBaseVersion') <> 'number'
   or (current_operation -> 'patch' ->> 'sourceScopeBaseVersion')::bigint < 0
   or jsonb_typeof(current_operation -> 'patch' -> 'targetScopeBaseVersion') <> 'number'
   or (current_operation -> 'patch' ->> 'targetScopeBaseVersion')::bigint < 0
   or $typeChecks then
  raise exception 'Ordered transfer has invalid field types' using errcode = '22023';
end if;
if exists (
  select 1
  from jsonb_object_keys(current_operation -> 'patch' -> 'targetScope') key
  where not (key = any(array[$targetNames]::text[]))
) or not ((current_operation -> 'patch' -> 'targetScope') ?&
    array[$targetNames]) then
  raise exception 'Ordered transfer target scope is incomplete' using errcode = '22023';
end if;
if not (${_rpcAuthorizationExpression(spec, RlsOperation.update, "(current_operation ->> 'entityId')::uuid")}) then
  raise exception 'Entity access denied' using errcode = '42501';
end if;
select * into canonical
from public.${spec.tableName}
where ${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
  and ${_orderMembershipSql(spec)};
if not found then
  raise exception 'Ordered entity not found' using errcode = 'P0002';
end if;
source_order_scope_key := $sourceKey;
target_order_scope_key := $targetKey;
if source_order_scope_key = target_order_scope_key then
  raise exception 'Ordered transfer must change scope' using errcode = '22023';
end if;
$hierarchyPartitionLock
perform pg_advisory_xact_lock(
  hashtextextended('${spec.className}:' || least(source_order_scope_key, target_order_scope_key), 0)
);
perform pg_advisory_xact_lock(
  hashtextextended('${spec.className}:' || greatest(source_order_scope_key, target_order_scope_key), 0)
);
select candidate.* into canonical
from public.${spec.tableName} candidate
where candidate.${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
  and ${_orderMembershipSql(spec, 'candidate')}
  and $lockedSourceKey = source_order_scope_key
for update;
if not found then
  raise exception 'Ordered entity left its source scope' using errcode = '40001';
end if;
$referenceValidation$cycleValidation
source_order_scope := ${_orderScopeRowJsonExpression(spec, 'canonical')};
target_order_scope := $targetScope;
insert into public.local_entity_order_scopes (entity_type, scope_key)
values
  ('${spec.className}', source_order_scope_key),
  ('${spec.className}', target_order_scope_key)
on conflict (entity_type, scope_key) do nothing;
select scope.version into source_order_scope_version
from public.local_entity_order_scopes scope
where scope.entity_type = '${spec.className}'
  and scope.scope_key = source_order_scope_key
for update;
select scope.version into target_order_scope_version
from public.local_entity_order_scopes scope
where scope.entity_type = '${spec.className}'
  and scope.scope_key = target_order_scope_key
for update;
if (current_operation -> 'patch' ->> 'sourceScopeBaseVersion')::bigint
      > source_order_scope_version
   or (current_operation -> 'patch' ->> 'targetScopeBaseVersion')::bigint
      > target_order_scope_version then
  raise exception 'Ordered scope base version is ahead of the server'
    using errcode = '22023';
end if;
if current_operation -> 'patch' ->> 'placement' = 'first' then
  lower_order_rank := 0;
  select member.${rank.columnName}::numeric into upper_order_rank
  from public.${spec.tableName} member
  where ${_orderMembershipSql(spec, 'member')}
    and $targetMemberCheck
  order by member.${rank.columnName}, member.${spec.idField.columnName}
  limit 1;
  if not found then upper_order_rank := $maximum::numeric; end if;
else
  upper_order_rank := $maximum::numeric;
  select member.${rank.columnName}::numeric into lower_order_rank
  from public.${spec.tableName} member
  where ${_orderMembershipSql(spec, 'member')}
    and $targetMemberCheck
  order by member.${rank.columnName} desc, member.${spec.idField.columnName} desc
  limit 1;
  if not found then lower_order_rank := 0; end if;
end if;
next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
if next_order_rank <= lower_order_rank or next_order_rank >= upper_order_rank then
$recovery
end if;
update public.${spec.tableName}
set $targetAssignments,
    ${rank.columnName} = lpad(next_order_rank::text, 78, '0'),
    ${spec.serverVersionField.columnName} = canonical.${spec.serverVersionField.columnName} + 1
where ${spec.idField.columnName} = canonical.${spec.idField.columnName}
returning * into canonical;
update public.local_entity_order_scopes scope
set version = scope.version + 1
where scope.entity_type = '${spec.className}'
  and scope.scope_key = source_order_scope_key
returning scope.version into source_order_scope_version;
update public.local_entity_order_scopes scope
set version = scope.version + 1
where scope.entity_type = '${spec.className}'
  and scope.scope_key = target_order_scope_key
returning scope.version into target_order_scope_version;
order_scope_versions := jsonb_build_array(
  jsonb_build_object('scope', source_order_scope, 'version', source_order_scope_version),
  jsonb_build_object('scope', target_order_scope, 'version', target_order_scope_version)
);
current_order_scope_version := null;''';
}

String _orderedReorderCommandSql(EntitySpec spec) {
  final rank = spec.orderRankField!;
  final scopeLookupExpression = _orderScopeRowExpression(spec, null);
  final lockedScopeExpression = _orderScopeRowExpression(spec, 'candidate');
  final memberScopeCheck = spec.hasRootOrderScope
      ? ''
      : ' and ${_orderScopeRowsMatch(spec, left: 'member', right: 'canonical')}';
  final memberAuthorization = _rpcAuthorizationExpression(
    spec,
    RlsOperation.update,
    'requested.member_id',
  );
  final maximum = GeneratedOrderRanks.upperBoundaryValue;
  return '''
if exists (
  select 1 from jsonb_object_keys(current_operation -> 'patch') key
  where not (key = any(array['orderedIds', 'scopeBaseVersion']::text[]))
) or not ((current_operation -> 'patch') ?&
    array['orderedIds', 'scopeBaseVersion']) then
  raise exception 'Exact reorder has invalid fields' using errcode = '22023';
end if;
if jsonb_typeof(current_operation -> 'patch' -> 'orderedIds') <> 'array'
   or jsonb_array_length(current_operation -> 'patch' -> 'orderedIds') = 0
   or jsonb_typeof(current_operation -> 'patch' -> 'scopeBaseVersion') <> 'number'
   or (current_operation -> 'patch' ->> 'scopeBaseVersion')::bigint < 0
   or exists (
     select 1
     from jsonb_array_elements(current_operation -> 'patch' -> 'orderedIds') item
     where jsonb_typeof(item) <> 'string'
   ) then
  raise exception 'Exact reorder has invalid field types' using errcode = '22023';
end if;
if (
  select count(distinct value)
  from jsonb_array_elements_text(current_operation -> 'patch' -> 'orderedIds')
) <> jsonb_array_length(current_operation -> 'patch' -> 'orderedIds') then
  raise exception 'Exact reorder identities must be unique' using errcode = '22023';
end if;
select $scopeLookupExpression into order_scope_key
from public.${spec.tableName}
where ${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
  and ${_orderMembershipSql(spec)};
if not found then
  raise exception 'Ordered entity not found' using errcode = 'P0002';
end if;
perform pg_advisory_xact_lock(
  hashtextextended('${spec.className}:' || order_scope_key, 0)
);
select candidate.* into canonical from public.${spec.tableName} candidate
where candidate.${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
  and ${_orderMembershipSql(spec, 'candidate')}
  and $lockedScopeExpression = order_scope_key
for update;
if not found then
  raise exception 'Ordered entity left its canonical scope' using errcode = '40001';
end if;
insert into public.local_entity_order_scopes (entity_type, scope_key)
values ('${spec.className}', order_scope_key)
on conflict (entity_type, scope_key) do nothing;
select scope.version into current_order_scope_version
from public.local_entity_order_scopes scope
where scope.entity_type = '${spec.className}'
  and scope.scope_key = order_scope_key
for update;
if (current_operation -> 'patch' ->> 'scopeBaseVersion')::bigint
    > current_order_scope_version then
  raise exception 'Ordered scope base version is ahead of the server'
    using errcode = '22023';
end if;
if exists (
  with requested as (
    select value::uuid as member_id
    from jsonb_array_elements_text(
      current_operation -> 'patch' -> 'orderedIds'
    )
  ), active_members as (
    select member.${spec.idField.columnName} as member_id
    from public.${spec.tableName} member
    where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
  )
  select 1
  from requested
  full outer join active_members using (member_id)
  where requested.member_id is null or active_members.member_id is null
) then
  raise exception 'Exact ordered membership changed' using errcode = '40001';
end if;
if exists (
  select 1
  from (
    select value::uuid as member_id
    from jsonb_array_elements_text(
      current_operation -> 'patch' -> 'orderedIds'
    )
  ) requested
  where not ($memberAuthorization)
) then
  raise exception 'Entity access denied' using errcode = '42501';
end if;
with requested as (
  select
    value::uuid as member_id,
    ordinality::numeric as position,
    jsonb_array_length(
      current_operation -> 'patch' -> 'orderedIds'
    )::numeric as scope_size
  from jsonb_array_elements_text(
    current_operation -> 'patch' -> 'orderedIds'
  ) with ordinality
)
update public.${spec.tableName} member
set ${rank.columnName} = lpad(
      trunc(($maximum::numeric * requested.position) /
        (requested.scope_size + 1))::text,
      78,
      '0'
    ),
    ${spec.serverVersionField.columnName} =
      member.${spec.serverVersionField.columnName} + 1
from requested
where member.${spec.idField.columnName} = requested.member_id;
select * into canonical from public.${spec.tableName}
where ${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid;
update public.local_entity_order_scopes scope
set version = scope.version + 1
where scope.entity_type = '${spec.className}'
  and scope.scope_key = order_scope_key
returning scope.version into current_order_scope_version;''';
}

String _orderedMoveCommandSql(EntitySpec spec) {
  final rank = spec.orderRankField!;
  final scopeLookupExpression = _orderScopeRowExpression(spec, null);
  final lockedScopeExpression = _orderScopeRowExpression(spec, 'candidate');
  final neighborScopeCheck = spec.hasRootOrderScope
      ? ''
      : ' and ${_orderScopeRowsMatch(spec, left: 'neighbor', right: 'canonical')}';
  final memberScopeCheck = spec.hasRootOrderScope
      ? ''
      : ' and ${_orderScopeRowsMatch(spec, left: 'member', right: 'canonical')}';
  final maximum = GeneratedOrderRanks.upperBoundaryValue;
  final resolveBounds = _orderedMoveBoundsSql(
    spec,
    rank: rank,
    neighborScopeCheck: neighborScopeCheck,
    maximum: maximum,
  );
  final indexedRecovery = _orderedIndexedWindowRecoverySql(
    spec,
    placementExpression: "current_operation -> 'patch' ->> 'placement'",
    memberScopeCheck: memberScopeCheck,
    excludeEntity: true,
    supportsAnchor: true,
    maximum: maximum,
  );
  final boundedRecovery =
      '''with ordered_scope as (
    select
      member.${spec.idField.columnName} as member_id,
      row_number() over (
        order by member.${rank.columnName}, member.${spec.idField.columnName}
      ) as position,
      count(*) over () as scope_size
    from public.${spec.tableName} member
    where ${_orderMembershipSql(spec, 'member')}$memberScopeCheck
  ), rebalanced as (
    select
      member_id,
      trunc(
        ($maximum::numeric * position::numeric) /
        (scope_size::numeric + 1)
      ) as next_rank
    from ordered_scope
  )
  update public.${spec.tableName} member
  set ${rank.columnName} = lpad(rebalanced.next_rank::text, 78, '0'),
      ${spec.serverVersionField.columnName} =
        member.${spec.serverVersionField.columnName} + 1
  from rebalanced
  where member.${spec.idField.columnName} = rebalanced.member_id;
  $resolveBounds
  next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
  if next_order_rank <= lower_order_rank
     or next_order_rank >= upper_order_rank then
    raise exception 'Ordered scope rank rebalance failed' using errcode = 'P0001';
  end if;''';
  final recovery = spec.cardinality == Cardinality.unbounded
      ? indexedRecovery
      : boundedRecovery;
  return '''
if exists (
  select 1 from jsonb_object_keys(current_operation -> 'patch') key
  where not (key = any(array['placement', 'anchorId', 'scopeBaseVersion']::text[]))
) or not ((current_operation -> 'patch') ?&
    array['placement', 'anchorId', 'scopeBaseVersion']) then
  raise exception 'Ordered move has invalid fields' using errcode = '22023';
end if;
if jsonb_typeof(current_operation -> 'patch' -> 'scopeBaseVersion') <> 'number'
   or (current_operation -> 'patch' ->> 'scopeBaseVersion')::bigint < 0
   or jsonb_typeof(current_operation -> 'patch' -> 'placement') <> 'string'
   or jsonb_typeof(current_operation -> 'patch' -> 'anchorId')
        not in ('string', 'null') then
  raise exception 'Ordered move has invalid field types' using errcode = '22023';
end if;
if current_operation -> 'patch' ->> 'placement'
      not in ('before', 'after', 'first', 'last')
   or ((current_operation -> 'patch' ->> 'placement') in ('before', 'after'))
      <> (current_operation -> 'patch' -> 'anchorId' <> 'null'::jsonb) then
  raise exception 'Ordered move has invalid placement and anchor'
    using errcode = '22023';
end if;
if not (${_rpcAuthorizationExpression(spec, RlsOperation.update, "(current_operation ->> 'entityId')::uuid")}) then
  raise exception 'Entity access denied' using errcode = '42501';
end if;
select $scopeLookupExpression into order_scope_key
from public.${spec.tableName}
where ${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
  and ${_orderMembershipSql(spec)};
if not found then
  raise exception 'Ordered entity not found' using errcode = 'P0002';
end if;
perform pg_advisory_xact_lock(
  hashtextextended('${spec.className}:' || order_scope_key, 0)
);
select candidate.* into canonical from public.${spec.tableName} candidate
where candidate.${spec.idField.columnName} = (current_operation ->> 'entityId')::uuid
  and ${_orderMembershipSql(spec, 'candidate')}
  and $lockedScopeExpression = order_scope_key
for update;
if not found then
  raise exception 'Ordered entity left its canonical scope' using errcode = '40001';
end if;
insert into public.local_entity_order_scopes (entity_type, scope_key)
values ('${spec.className}', order_scope_key)
on conflict (entity_type, scope_key) do nothing;
select scope.version into current_order_scope_version
from public.local_entity_order_scopes scope
where scope.entity_type = '${spec.className}'
  and scope.scope_key = order_scope_key
for update;
if (current_operation -> 'patch' ->> 'scopeBaseVersion')::bigint
    > current_order_scope_version then
  raise exception 'Ordered scope base version is ahead of the server'
    using errcode = '22023';
end if;
if current_operation -> 'patch' -> 'anchorId' <> 'null'::jsonb
   and current_operation ->> 'entityId' =
       current_operation -> 'patch' ->> 'anchorId' then
  raise exception 'Ordered entity cannot be its own anchor' using errcode = '22023';
end if;
$resolveBounds
next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
if next_order_rank <= lower_order_rank or next_order_rank >= upper_order_rank then
$recovery
end if;
update public.${spec.tableName}
set ${rank.columnName} = lpad(next_order_rank::text, 78, '0'),
    ${spec.serverVersionField.columnName} =
      ${spec.serverVersionField.columnName} + 1
where ${spec.idField.columnName} = canonical.${spec.idField.columnName}
returning * into canonical;
update public.local_entity_order_scopes scope
set version = scope.version + 1
where scope.entity_type = '${spec.className}'
  and scope.scope_key = order_scope_key
returning scope.version into current_order_scope_version;''';
}

String _orderedMoveBoundsSql(
  EntitySpec spec, {
  required FieldSpec rank,
  required String neighborScopeCheck,
  required String maximum,
}) =>
    '''
if current_operation -> 'patch' ->> 'placement' = 'first' then
  lower_order_rank := 0;
  select neighbor.${rank.columnName}::numeric into upper_order_rank
  from public.${spec.tableName} neighbor
  where ${_orderMembershipSql(spec, 'neighbor')}
    and neighbor.${spec.idField.columnName} <>
        (current_operation ->> 'entityId')::uuid$neighborScopeCheck
  order by neighbor.${rank.columnName}, neighbor.${spec.idField.columnName}
  limit 1;
  if not found then
    upper_order_rank := $maximum::numeric;
  end if;
elsif current_operation -> 'patch' ->> 'placement' = 'last' then
  upper_order_rank := $maximum::numeric;
  select neighbor.${rank.columnName}::numeric into lower_order_rank
  from public.${spec.tableName} neighbor
  where ${_orderMembershipSql(spec, 'neighbor')}
    and neighbor.${spec.idField.columnName} <>
        (current_operation ->> 'entityId')::uuid$neighborScopeCheck
  order by neighbor.${rank.columnName} desc,
           neighbor.${spec.idField.columnName} desc
  limit 1;
  if not found then
    lower_order_rank := 0;
  end if;
else
  select neighbor.${rank.columnName}::numeric into anchor_order_rank
  from public.${spec.tableName} neighbor
  where neighbor.${spec.idField.columnName} =
      (current_operation -> 'patch' ->> 'anchorId')::uuid
    and ${_orderMembershipSql(spec, 'neighbor')}$neighborScopeCheck;
  if not found then
    raise exception 'Ordered anchor is outside the canonical scope'
      using errcode = '22023';
  end if;
  if current_operation -> 'patch' ->> 'placement' = 'before' then
    upper_order_rank := anchor_order_rank;
    select neighbor.${rank.columnName}::numeric into lower_order_rank
    from public.${spec.tableName} neighbor
    where ${_orderMembershipSql(spec, 'neighbor')}
      and neighbor.${spec.idField.columnName} <>
          (current_operation ->> 'entityId')::uuid$neighborScopeCheck
      and (neighbor.${rank.columnName},
           neighbor.${spec.idField.columnName}) <
          (lpad(anchor_order_rank::text, 78, '0'),
           (current_operation -> 'patch' ->> 'anchorId')::uuid)
    order by neighbor.${rank.columnName} desc,
             neighbor.${spec.idField.columnName} desc
    limit 1;
    if not found then
      lower_order_rank := 0;
    end if;
  else
    lower_order_rank := anchor_order_rank;
    select neighbor.${rank.columnName}::numeric into upper_order_rank
    from public.${spec.tableName} neighbor
    where ${_orderMembershipSql(spec, 'neighbor')}
      and neighbor.${spec.idField.columnName} <>
          (current_operation ->> 'entityId')::uuid$neighborScopeCheck
      and (neighbor.${rank.columnName},
           neighbor.${spec.idField.columnName}) >
          (lpad(anchor_order_rank::text, 78, '0'),
           (current_operation -> 'patch' ->> 'anchorId')::uuid)
    order by neighbor.${rank.columnName}, neighbor.${spec.idField.columnName}
    limit 1;
    if not found then
      upper_order_rank := $maximum::numeric;
    end if;
  end if;
end if;''';

String _indentSql(String source, int spaces) {
  final prefix = ' ' * spaces;
  return source
      .split('\n')
      .map((line) => line.isEmpty ? '' : '$prefix$line')
      .join('\n');
}

void _emitSyncInfrastructure(
  StringBuffer buffer,
  EntitySpec spec, {
  required bool includeSharedTables,
  required bool includeOrderScopeTable,
}) {
  final ownerColumn = spec.ownerField.columnName;
  buffer
    ..writeln()
    ..writeln('do \$\$')
    ..writeln('begin')
    ..writeln(
      "  if exists (select 1 from pg_publication where pubname = "
      "'supabase_realtime') and not exists (select 1 from "
      "pg_publication_tables where pubname = 'supabase_realtime' and "
      "schemaname = 'public' and tablename = '${spec.tableName}') then",
    )
    ..writeln(
      '    alter publication supabase_realtime add table '
      'public.${spec.tableName};',
    )
    ..writeln('  end if;')
    ..writeln('end;')
    ..writeln('\$\$;')
    ..writeln(_collaborationPublicationSql(spec));
  if (includeSharedTables) {
    buffer
      ..writeln()
      ..writeln(
        'create table if not exists public.local_entity_operation_receipts (',
      )
      ..writeln('  operation_id uuid primary key,')
      ..writeln('  user_id uuid not null,')
      ..writeln('  entity_type text not null,')
      ..writeln('  entity_id uuid not null,')
      ..writeln('  result jsonb not null,')
      ..writeln('  accepted_at timestamptz not null default now()')
      ..writeln(');')
      ..writeln(
        'alter table public.local_entity_operation_receipts enable row level security;',
      )
      ..writeln(
        'drop policy if exists local_entity_receipts_owner on '
        'public.local_entity_operation_receipts;',
      )
      ..writeln(
        'create policy local_entity_receipts_owner on '
        'public.local_entity_operation_receipts for all to authenticated '
        'using ((select auth.uid()) = user_id) '
        'with check ((select auth.uid()) = user_id);',
      )
      ..writeln(
        'revoke all on public.local_entity_operation_receipts '
        'from anon, authenticated;',
      );
    if (includeOrderScopeTable) {
      buffer
        ..writeln()
        ..writeln(
          'create table if not exists public.local_entity_order_scopes (',
        )
        ..writeln('  entity_type text not null,')
        ..writeln('  scope_key text not null,')
        ..writeln('  version bigint not null default 0 check (version >= 0),')
        ..writeln('  primary key (entity_type, scope_key)')
        ..writeln(');')
        ..writeln(
          'alter table public.local_entity_order_scopes enable row level security;',
        )
        ..writeln(
          'revoke all on public.local_entity_order_scopes '
          'from anon, authenticated;',
        );
    }
    buffer
      ..writeln()
      ..writeln('create table if not exists public.local_entity_changes (')
      ..writeln('  sequence bigint generated always as identity primary key,')
      ..writeln('  entity_type text not null,')
      ..writeln('  entity_id uuid not null,')
      ..writeln('  owner_id uuid not null,')
      ..writeln('  server_version bigint not null,')
      ..writeln('  operation_id uuid,')
      ..writeln('  audience_user_id uuid,')
      ..writeln('  is_revocation boolean not null default false,')
      ..writeln('  record jsonb not null,')
      ..writeln('  changed_at timestamptz not null default now()')
      ..writeln(');')
      ..writeln(
        'create index if not exists local_entity_changes_type_sequence_idx on '
        'public.local_entity_changes (entity_type, sequence);',
      )
      ..writeln(
        'create index if not exists local_entity_changes_identity_idx on '
        'public.local_entity_changes '
        '(entity_type, entity_id, audience_user_id, sequence);',
      )
      ..writeln(
        'alter table public.local_entity_changes enable row level security;',
      )
      ..writeln(
        'revoke all on public.local_entity_changes from anon, authenticated;',
      );
  }
  buffer
    ..writeln()
    ..writeln(
      'create or replace function public.capture_${spec.tableName}_change()',
    )
    ..writeln('returns trigger')
    ..writeln('language plpgsql')
    ..writeln('security definer')
    ..writeln("set search_path = ''")
    ..writeln('as \$\$')
    ..writeln('begin')
    ..writeln(
      "  delete from public.local_entity_changes where entity_type = "
      "'${spec.className}' and entity_id = new.${spec.idField.columnName} "
      'and audience_user_id is null;',
    )
    ..writeln(
      '  insert into public.local_entity_changes '
      '(entity_type, entity_id, owner_id, server_version, operation_id, '
      'audience_user_id, is_revocation, record)',
    )
    ..writeln(
      "  values ('${spec.className}', new.${spec.idField.columnName}, "
      'new.$ownerColumn, new.${spec.serverVersionField.columnName}, '
      "nullif(current_setting('app.operation_id', true), '')::uuid, "
      'null, false, to_jsonb(new));',
    )
    ..writeln('  return new;')
    ..writeln('end;')
    ..writeln('\$\$;')
    ..writeln(
      'revoke all on function public.capture_${spec.tableName}_change() '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'drop trigger if exists ${spec.tableName}_capture_change '
      'on public.${spec.tableName};',
    )
    ..writeln(
      'create trigger ${spec.tableName}_capture_change after insert or update '
      'on public.${spec.tableName} for each row execute function '
      'public.capture_${spec.tableName}_change();',
    );
}

void _emitEntityFunctions(
  StringBuffer buffer,
  EntitySpec spec, {
  EntitySpec? activitySource,
  required bool includePull,
}) {
  final mutable = spec.fields.where(
    (field) => !field.isId && spec.isPatchable(field),
  );
  final commandFields = spec.commands
      .map(
        (command) => spec.fields.singleWhere(
          (field) => field.name == command.targetField,
        ),
      )
      .toSet();
  final assignments = <FieldSpec>{...mutable, ...commandFields}
      .map((field) {
        final operation = spec.isCommandOnly(field) ? 'delete' : 'patch';
        return '    ${field.columnName} = case when p_operation = \'$operation\' '
            'and p_patch ? \'${field.name}\' '
            'then ${_jsonCast("p_patch -> '${field.name}'", field)} '
            'else current_row.${field.columnName} end';
      })
      .join(',\n');
  final createFields = spec.fields
      .where((field) => field.inCreatePayload && !spec.isCommandOnly(field))
      .toList(growable: false);
  final createColumns = createFields
      .map((field) => field.columnName)
      .join(', ');
  final createValues = createFields
      .map(
        (field) =>
            _jsonCast("current_operation -> 'patch' -> '${field.name}'", field),
      )
      .join(', ');
  final createFieldNames = createFields
      .map((field) => "'${field.name}'")
      .join(', ');
  final createRequiredFieldNames = createFields
      .where(
        (field) => !spec.hasOrderedCapability || field != spec.orderRankField,
      )
      .map((field) => "'${field.name}'")
      .join(', ');
  final stateOperations = [
    if (spec.canUpdate) 'patch',
    if (spec.canDelete) 'delete',
  ];
  final supportedOperations = [
    if (spec.canCreate) 'create',
    ...stateOperations,
    if (spec.canCommand) 'command',
  ];
  final stateOperationSql = stateOperations.map((name) => "'$name'").join(', ');
  final supportedOperationSql = supportedOperations
      .map((name) => "'$name'")
      .join(', ');
  final updateAuthorizationSql = spec.canUpdate
      ? """
  if p_operation = 'patch' and not (${_rpcAuthorizationExpression(spec, RlsOperation.update, 'p_id')}) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;"""
      : '';
  final deleteAuthorizationSql = spec.canDelete
      ? """
  if p_operation = 'delete' and not (${_rpcAuthorizationExpression(spec, RlsOperation.delete, 'p_id')}) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;"""
      : '';

  if (supportedOperations.isNotEmpty) {
    _emitProtocolUpcaster(buffer, spec);

    if (spec.hasStateMutations) {
      buffer
        ..writeln()
        ..writeln(
          'create or replace function public.apply_${spec.tableName}_patch(',
        )
        ..writeln('  p_id uuid,')
        ..writeln('  p_base_server_version bigint,')
        ..writeln('  p_operation text,')
        ..writeln('  p_patch jsonb')
        ..writeln(') returns public.${spec.tableName}')
        ..writeln('language plpgsql')
        ..writeln('security definer')
        ..writeln("set search_path = ''")
        ..writeln('as \$\$')
        ..writeln('declare')
        ..writeln('  current_row public.${spec.tableName};')
        ..writeln('  updated_row public.${spec.tableName};')
        ..writeln('begin')
        ..writeln('  if auth.uid() is null then')
        ..writeln(
          "    raise exception 'Authentication required' using errcode = '42501';",
        )
        ..writeln('  end if;')
        ..writeln('  if p_operation not in ($stateOperationSql) then')
        ..writeln(
          "    raise exception 'Unsupported operation' using errcode = '22023';",
        )
        ..writeln('  end if;')
        ..writeln(updateAuthorizationSql)
        ..writeln(deleteAuthorizationSql)
        ..writeln(_patchKeyValidation(spec, mutable, commandFields))
        ..writeln(_referenceValidation(spec, 'p_patch', indent: '  '))
        ..writeln(
          '  select * into current_row from public.${spec.tableName} '
          'where ${spec.idField.columnName} = p_id for update;',
        )
        ..writeln('  if not found then')
        ..writeln(
          "    raise exception 'Entity not found' using errcode = 'P0002';",
        )
        ..writeln('  end if;');
      final fieldAuthorization = _fieldUpdateAuthorizationSql(spec);
      if (fieldAuthorization.isNotEmpty) {
        buffer.writeln(fieldAuthorization);
      }
      final actionValidation = _actionValidationSql(spec);
      if (actionValidation.isNotEmpty) {
        buffer.writeln(actionValidation);
      }
      final transitionValidation = _transitionValidationSql(spec);
      if (transitionValidation.isNotEmpty) {
        buffer.writeln(transitionValidation);
      }
      buffer
        ..writeln(
          '  if current_row.${spec.serverVersionField.columnName} '
          '<> p_base_server_version then',
        )
        ..writeln(
          "    raise exception 'Version conflict' using errcode = '40001';",
        )
        ..writeln('  end if;')
        ..writeln('  update public.${spec.tableName}')
        ..writeln('  set')
        ..writeln(assignments)
        ..writeln(
          '    , ${spec.serverVersionField.columnName} = '
          'current_row.${spec.serverVersionField.columnName} + 1',
        )
        ..writeln('  where ${spec.idField.columnName} = p_id')
        ..writeln('  returning * into updated_row;')
        ..writeln('  return updated_row;')
        ..writeln('end;')
        ..writeln('\$\$;');
    }

    buffer
      ..writeln()
      ..writeln(
        'create or replace function public.push_${spec.tableName}_operations('
        'p_operations jsonb)',
      )
      ..writeln('returns jsonb')
      ..writeln('language plpgsql')
      ..writeln('security definer')
      ..writeln("set search_path = ''")
      ..writeln('as \$\$')
      ..writeln('declare')
      ..writeln('  current_operation jsonb;')
      ..writeln('  operation_uuid uuid;')
      ..writeln('  receipt_result jsonb;')
      ..writeln('  canonical public.${spec.tableName};')
      ..write(
        spec.hasOrderedCapability
            ? '  lower_order_rank numeric;\n'
                  '  upper_order_rank numeric;\n'
                  '  anchor_order_rank numeric;\n'
                  '  next_order_rank numeric;\n'
                  '  current_order_scope_version bigint;\n'
                  '  order_scope_key text;\n'
                  '  order_scope_membership_changed boolean;\n'
                  '${spec.cardinality == Cardinality.unbounded ? '  rebalance_window_size integer;\n  rebalance_member_ids uuid[];\n  rebalance_member_count integer;\n  rebalance_outside_rank numeric;\n  rebalance_lower_rank numeric;\n  rebalance_upper_rank numeric;\n  rebalance_step numeric;\n  rebalance_has_outside boolean;\n' : ''}'
                  "  order_scope_versions jsonb := '[]'::jsonb;\n"
                  '${spec.orderScopeTransferAction == null ? '' : '  source_order_scope_key text;\n  target_order_scope_key text;\n  source_order_scope_version bigint;\n  target_order_scope_version bigint;\n  source_order_scope jsonb;\n  target_order_scope jsonb;\n'}'
                  '  related_changes jsonb;\n'
            : '',
      )
      ..writeln('  change_sequence bigint;')
      ..writeln("  results jsonb := '[]'::jsonb;")
      ..writeln('begin')
      ..writeln('  if auth.uid() is null then')
      ..writeln(
        "    raise exception 'Authentication required' using errcode = '42501';",
      )
      ..writeln('  end if;')
      ..writeln("  if jsonb_typeof(p_operations) <> 'array' then")
      ..writeln(
        "    raise exception 'Operations must be an array' using errcode = '22023';",
      )
      ..writeln('  end if;')
      ..writeln('  if jsonb_array_length(p_operations) > 100 then')
      ..writeln(
        "    raise exception 'At most 100 operations are allowed per batch' "
        "using errcode = '22023';",
      )
      ..writeln('  end if;')
      ..writeln(
        '  for current_operation in select value from '
        'jsonb_array_elements(p_operations) loop',
      )
      ..write(
        spec.hasOrderedCapability
            ? '    current_order_scope_version := null;\n'
                  '    order_scope_membership_changed := false;\n'
                  "    order_scope_versions := '[]'::jsonb;\n"
            : '',
      )
      ..writeln(
        '    current_operation := public.upcast_${spec.tableName}_operation('
        'current_operation);',
      )
      ..writeln(
        "    operation_uuid := (current_operation ->> 'operationId')::uuid;",
      )
      ..writeln(
        "    if current_operation ->> 'entityType' <> '${spec.className}' then",
      )
      ..writeln(
        "      raise exception 'Unexpected entity type' using errcode = '22023';",
      )
      ..writeln('    end if;')
      ..writeln(
        "    if coalesce((current_operation ->> 'protocolVersion')::integer, 0) <> ${spec.protocolVersion} then",
      )
      ..writeln(
        "      raise exception 'Unsupported protocol version' using errcode = '22023';",
      )
      ..writeln('    end if;')
      ..writeln(
        "    if jsonb_typeof(current_operation -> 'patch') <> 'object' then",
      )
      ..writeln(
        "      raise exception 'Patch must be an object' using errcode = '22023';",
      )
      ..writeln('    end if;')
      ..writeln(
        '    select receipt.result into receipt_result from '
        'public.local_entity_operation_receipts receipt '
        'where receipt.operation_id = operation_uuid '
        'and receipt.user_id = auth.uid();',
      )
      ..writeln('    if found then')
      ..writeln(
        '      results := results || jsonb_build_array(receipt_result);',
      )
      ..writeln('      continue;')
      ..writeln('    end if;')
      ..writeln(
        "    perform set_config('app.operation_id', operation_uuid::text, true);",
      )
      ..writeln(
        "    if current_operation ->> 'operation' not in ($supportedOperationSql) then",
      )
      ..writeln(
        "      raise exception 'Unsupported operation' using errcode = '22023';",
      )
      ..writeln('    end if;')
      ..writeln(
        _pushOperationRoutingSql(
          spec,
          activitySource: activitySource,
          createColumns: createColumns,
          createValues: createValues,
          createFieldNames: createFieldNames,
          createRequiredFieldNames: createRequiredFieldNames,
        ),
      )
      ..writeln(
        '    select changes.sequence into change_sequence from '
        'public.local_entity_changes changes where '
        'changes.operation_id = operation_uuid${spec.hasOrderedCapability ? " and changes.entity_type = '${spec.className}' and changes.entity_id = canonical.${spec.idField.columnName}" : ''} '
        'order by changes.sequence desc '
        'limit 1;',
      )
      ..writeln('    if change_sequence is null then')
      ..writeln(
        "      raise exception 'Accepted operation has no change-log entry' "
        "using errcode = 'P0001';",
      )
      ..writeln('    end if;')
      ..write(
        spec.hasOrderedCapability
            ? "    select coalesce(jsonb_agg(jsonb_build_object("
                  "'entityType', changes.entity_type, "
                  "'record', changes.record, "
                  "'sequence', changes.sequence, "
                  "'operationId', changes.operation_id, "
                  "'serverVersion', changes.server_version) "
                  "order by changes.sequence), '[]'::jsonb) "
                  'into related_changes '
                  'from public.local_entity_changes changes '
                  'where changes.operation_id = operation_uuid '
                  'and changes.audience_user_id is null '
                  'and not changes.is_revocation '
                  "and not (changes.entity_type = '${spec.className}' "
                  'and changes.entity_id = canonical.${spec.idField.columnName});\n'
            : '',
      )
      ..write(
        spec.hasOrderedCapability
            ? '    if current_order_scope_version is not null then\n'
                  '      order_scope_versions := jsonb_build_array(\n'
                  "        jsonb_build_object('scope', "
                  '${_orderScopeRowJsonExpression(spec, 'canonical')}, '
                  "'version', current_order_scope_version)\n"
                  '      );\n'
                  '    end if;\n'
            : '',
      )
      ..writeln(
        spec.hasOrderedCapability
            ? "    receipt_result := jsonb_build_object("
                  "'record', to_jsonb(canonical), 'sequence', change_sequence, "
                  "'operationId', operation_uuid, "
                  "'${EntityConventions.serverVersionFieldName}', "
                  'canonical.${spec.serverVersionField.columnName}, '
                  "'scopeVersions', order_scope_versions, "
                  "'relatedChanges', related_changes);"
            : "    receipt_result := jsonb_build_object("
                  "'record', to_jsonb(canonical), 'sequence', change_sequence, "
                  "'operationId', operation_uuid, "
                  "'${EntityConventions.serverVersionFieldName}', "
                  'canonical.${spec.serverVersionField.columnName});',
      )
      ..writeln(
        '    insert into public.local_entity_operation_receipts '
        '(operation_id, user_id, entity_type, entity_id, result) values '
        "(operation_uuid, auth.uid(), '${spec.className}', "
        'canonical.${spec.idField.columnName}, receipt_result);',
      )
      ..writeln('    results := results || jsonb_build_array(receipt_result);')
      ..writeln('  end loop;')
      ..writeln('  return results;')
      ..writeln('end;')
      ..writeln('\$\$;');
  }
  if (!includePull) {
    if (supportedOperations.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'revoke all on function public.upcast_${spec.tableName}_operation(jsonb) '
          'from $supabaseApiRoles;',
        );
      if (spec.hasStateMutations) {
        buffer.writeln(
          'revoke all on function public.apply_${spec.tableName}_patch('
          'uuid, bigint, text, jsonb) from $supabaseApiRoles;',
        );
      }
      buffer
        ..writeln(
          'revoke all on function public.push_${spec.tableName}_operations(jsonb) '
          'from $supabaseApiRoles;',
        )
        ..writeln(
          'grant execute on function public.push_${spec.tableName}_operations('
          'jsonb) to authenticated;',
        );
    }
    return;
  }
  buffer
    ..writeln()
    ..writeln(
      'create or replace function public.pull_${spec.tableName}_changes('
      'p_after_sequence bigint)',
    )
    ..writeln('returns jsonb')
    ..writeln('language plpgsql')
    ..writeln('security definer')
    ..writeln("set search_path = ''")
    ..writeln('stable')
    ..writeln('as \$\$')
    ..writeln('declare')
    ..writeln("  page jsonb := '[]'::jsonb;")
    ..writeln('  page_count integer;')
    ..writeln('  next_cursor bigint;')
    ..writeln('begin')
    ..writeln('  if auth.uid() is null then')
    ..writeln(
      "    raise exception 'Authentication required' using errcode = '42501';",
    )
    ..writeln('  end if;')
    ..writeln(
      "  select coalesce(jsonb_agg(jsonb_build_object('sequence', visible.sequence, "
      "'record', visible.record, 'server_version', visible.server_version, "
      "'operation_id', visible.operation_id, 'is_revocation', "
      "visible.is_revocation) order by visible.sequence), '[]'::jsonb)",
    )
    ..writeln('  into page')
    ..writeln('  from (')
    ..writeln(
      '    select changes.sequence, changes.record, changes.server_version, '
      'changes.operation_id, '
      '(changes.is_revocation and changes.audience_user_id = auth.uid()) '
      'as is_revocation',
    )
    ..writeln('    from public.local_entity_changes changes')
    ..writeln(
      '    join public.${spec.tableName} entity on '
      'entity.${spec.idField.columnName} = changes.entity_id',
    )
    ..writeln(
      "    where changes.entity_type = '${spec.className}' "
      'and changes.sequence > p_after_sequence '
      'and ((changes.audience_user_id is null and '
      '(${_rpcAuthorizationExpression(spec, RlsOperation.select, 'entity.${spec.idField.columnName}')})) '
      'or changes.audience_user_id = auth.uid())',
    )
    ..writeln('    order by changes.sequence')
    ..writeln('    limit 500')
    ..writeln('  ) visible;')
    ..writeln('  page_count := jsonb_array_length(page);')
    ..writeln('  if page_count = 500 then')
    ..writeln(
      "    next_cursor := (page -> (page_count - 1) ->> 'sequence')::bigint;",
    )
    ..writeln('  else')
    ..writeln(
      '    select coalesce(max(changes.sequence), p_after_sequence) into next_cursor '
      'from public.local_entity_changes changes;',
    )
    ..writeln('  end if;')
    ..writeln(
      "  return jsonb_build_object('changes', page, 'nextSequence', next_cursor, "
      "'hasMore', page_count = 500);",
    )
    ..writeln('end;')
    ..writeln('\$\$;')
    ..writeln()
    ..writeln(
      'revoke all on function public.upcast_${spec.tableName}_operation(jsonb) '
      'from $supabaseApiRoles;',
    );
  if (spec.hasStateMutations) {
    buffer.writeln(
      'revoke all on function public.apply_${spec.tableName}_patch('
      'uuid, bigint, text, jsonb) from $supabaseApiRoles;',
    );
  }
  buffer
    ..writeln(
      'revoke all on function public.push_${spec.tableName}_operations(jsonb) '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'revoke all on function public.pull_${spec.tableName}_changes(bigint) '
      'from $supabaseApiRoles;',
    )
    ..writeln(
      'grant execute on function public.push_${spec.tableName}_operations('
      'jsonb) to authenticated;',
    )
    ..writeln(
      'grant execute on function public.pull_${spec.tableName}_changes(bigint) '
      'to authenticated;',
    );
}

String _transitionValidationSql(EntitySpec spec) {
  final sections = <String>[];
  for (final field in spec.fields.where(
    (candidate) => candidate.transitions.isNotEmpty,
  )) {
    final next = '(${_jsonCast("p_patch -> '${field.name}'", field)})';
    final allowed = field.transitions
        .map((transition) {
          final principals = transition.principals.isEmpty
              ? spec.security.grants
                    .where((grant) => grant.operation == RlsOperation.update)
                    .map((grant) => grant.principal)
              : transition.principals;
          final actor = principals
              .map(
                (principal) => _principalByIdExpression(
                  spec,
                  principal,
                  'p_id',
                  operation: RlsOperation.update,
                ),
              )
              .toSet()
              .join(' or ');
          return '(current_row.${field.columnName} = '
              "${_sqlLiteral(transition.fromWire)} and $next = "
              '${_sqlLiteral(transition.toWire)} and ($actor))';
        })
        .join(' or ');
    sections.add('''
  if p_operation = 'patch' and p_patch ? '${field.name}'
     and current_row.${field.columnName} is distinct from $next
     and not ($allowed) then
    raise exception 'State transition is not allowed' using errcode = '23514';
  end if;''');
  }
  return sections.join('\n');
}

String _fieldUpdateAuthorizationSql(EntitySpec spec) {
  final sections = <String>[];
  for (final field in spec.fields.where(
    (candidate) => candidate.updatePrincipals.isNotEmpty,
  )) {
    final allowed = field.updatePrincipals
        .map(
          (principal) => _principalByIdExpression(
            spec,
            principal,
            'p_id',
            operation: RlsOperation.update,
          ),
        )
        .toSet()
        .join(' or ');
    sections.add('''
  if p_operation = 'patch' and p_patch ? '${field.name}'
     and not ($allowed) then
    raise exception 'Field update access denied' using errcode = '42501';
  end if;''');
  }
  return sections.join('\n');
}

String _actionValidationSql(EntitySpec spec) {
  if (spec.ordinaryActions.isEmpty) return '';
  final sections = <String>[];
  final actionFields =
      spec.ordinaryActions
          .expand((action) => action.targetFields)
          .toSet()
          .toList()
        ..sort();
  for (final fieldName in actionFields) {
    final matchingActions = spec.ordinaryActions.where(
      (action) => action.targetFields.contains(fieldName),
    );
    final allowed = matchingActions
        .map((action) {
          final keys = action.targetFields.map((name) => "'$name'").join(', ');
          final conditions = <String>["p_patch ?& array[$keys]::text[]"];
          for (final assignment in action.assignments) {
            final field = spec.fields.singleWhere(
              (field) => field.name == assignment.fieldName,
            );
            final source = "p_patch -> '${field.name}'";
            conditions.add(switch (assignment.kind) {
              ActionValueKind.literal =>
                '(${_jsonCast(source, field)}) is not distinct from '
                    '${_sqlLiteral(field.isEnum ? snakeCase(assignment.literal! as String) : assignment.literal)}',
              ActionValueKind.clockNow =>
                "$source <> 'null'::jsonb${field.nullable ? ' and (current_row.${field.columnName} is null or current_row.${field.columnName} is not distinct from (${_jsonCast(source, field)}))' : ''}",
              ActionValueKind.clear => "$source = 'null'::jsonb",
            });
          }
          return '(${conditions.join(' and ')})';
        })
        .join(' or ');
    sections.add('''
  if p_operation = 'patch' and p_patch ? '$fieldName'
     and not ($allowed) then
    raise exception 'Patch does not match a declared entity action' using errcode = '22023';
  end if;''');
  }
  return sections.join('\n');
}

String _initialStateValidationSql(
  EntitySpec spec,
  String patchExpression, {
  required String indent,
}) {
  final sections = <String>[];
  for (final field in spec.fields.where(
    (candidate) => candidate.transitions.isNotEmpty,
  )) {
    final value = _jsonCast("$patchExpression -> '${field.name}'", field);
    sections.add(
      '''${indent}if ($value) is distinct from ${_sqlLiteral(field.persistedDefaultValue)} then
$indent  raise exception 'Invalid initial workflow state' using errcode = '23514';
${indent}end if;''',
    );
  }
  return sections.join('\n');
}

String _actionInitialStateValidationSql(
  EntitySpec spec,
  String patchExpression, {
  required String indent,
}) {
  final fields = spec.fields.where(
    (field) =>
        spec.isFixedActionTarget(field) &&
        field.transitions.isEmpty &&
        (field.nullable || field.defaultValue != null),
  );
  return fields
      .map((field) {
        final value = _jsonCast("$patchExpression -> '${field.name}'", field);
        final expected = _sqlLiteral(field.persistedDefaultValue);
        return '''${indent}if ($value) is distinct from $expected then
$indent  raise exception 'Invalid initial entity action state' using errcode = '23514';
${indent}end if;''';
      })
      .join('\n');
}

String _principalByIdExpression(
  EntitySpec spec,
  RlsPrincipal principal,
  String idExpression, {
  RlsOperation operation = RlsOperation.select,
}) => switch (principal) {
  RlsPrincipal.owner => 'public.is_${spec.tableName}_owner($idExpression)',
  RlsPrincipal.participant =>
    'public.is_${spec.tableName}_participant($idExpression)',
  RlsPrincipal.collaborator =>
    'public.is_${spec.tableName}_collaborator($idExpression)',
  RlsPrincipal.reference =>
    'public.is_${spec.tableName}_reference($idExpression)',
  RlsPrincipal.relationship =>
    'public.is_${spec.tableName}_relationship_${operation.name}('
        '$idExpression)',
  RlsPrincipal.authenticated => 'auth.uid() is not null',
};

void _emitProtocolUpcaster(StringBuffer buffer, EntitySpec spec) {
  buffer
    ..writeln()
    ..writeln(
      'create or replace function public.upcast_${spec.tableName}_operation('
      'p_operation jsonb)',
    )
    ..writeln('returns jsonb')
    ..writeln('language plpgsql')
    ..writeln('immutable')
    ..writeln("set search_path = ''")
    ..writeln('as \$\$')
    ..writeln('declare')
    ..writeln('  current_version integer;')
    ..writeln('begin')
    ..writeln(
      "  current_version := coalesce((p_operation ->> 'protocolVersion')::integer, 0);",
    )
    ..writeln(
      '  if current_version < 1 or current_version > ${spec.protocolVersion} then',
    )
    ..writeln(
      "    raise exception 'Unsupported protocol version' using errcode = '22023';",
    )
    ..writeln('  end if;')
    ..writeln("  if jsonb_typeof(p_operation -> 'patch') <> 'object' then")
    ..writeln(
      "    raise exception 'Patch must be an object' using errcode = '22023';",
    )
    ..writeln('  end if;');

  for (var version = 2; version <= spec.protocolVersion; version++) {
    buffer.writeln('  if current_version < $version then');
    for (final field in spec.fields.where(
      (field) => field.sinceProtocolVersion == version && field.inCreatePayload,
    )) {
      final renamedFrom = field.renamedFrom;
      if (renamedFrom != null) {
        buffer
          ..writeln(
            "    if (p_operation -> 'patch') ? '$renamedFrom' and not "
            "((p_operation -> 'patch') ? '${field.name}') then",
          )
          ..writeln(
            "      p_operation := jsonb_set(p_operation, '{patch,${field.name}}', "
            "p_operation -> 'patch' -> '$renamedFrom', true);",
          )
          ..writeln('    end if;');
        buffer.writeln(
          "    p_operation := jsonb_set(p_operation, '{patch}', "
          "(p_operation -> 'patch') - '$renamedFrom');",
        );
      }
      if (!spec.isCommandOnly(field)) {
        final defaultValue =
            field.persistedDefaultValue ?? (field.nullable ? null : null);
        buffer
          ..writeln(
            "    if p_operation ->> 'operation' = 'create' and not "
            "((p_operation -> 'patch') ? '${field.name}') then",
          )
          ..writeln(
            "      p_operation := jsonb_set(p_operation, '{patch,${field.name}}', "
            '${_jsonbLiteral(defaultValue)}, true);',
          )
          ..writeln('    end if;');
      }
    }
    buffer
      ..writeln(
        "    p_operation := jsonb_set(p_operation, '{protocolVersion}', "
        "'$version'::jsonb, true);",
      )
      ..writeln('    current_version := $version;')
      ..writeln('  end if;');
  }
  buffer
    ..writeln('  return p_operation;')
    ..writeln('end;')
    ..writeln('\$\$;');
}

String _referenceValidation(
  EntitySpec spec,
  String patchExpression, {
  required String indent,
}) {
  final lines = <String>[];
  for (final field in spec.fields) {
    final reference = field.reference;
    if (reference == null) continue;
    final id = "($patchExpression ->> '${field.name}')::uuid";
    final isWorkflowMembershipTarget =
        reference.targetCollaboration?.isWorkflow == true &&
        reference.targetCollaboration!.membershipTable == spec.tableName;
    final requiresOwnerReference =
        field.isComposition || isWorkflowMembershipTarget;
    final principals = requiresOwnerReference
        ? const [RlsPrincipal.owner]
        : reference.targetSelectPrincipals;
    final allowed = requiresOwnerReference
        ? principals
              .map(
                (principal) =>
                    _targetPrincipalByIdExpression(reference, principal, id),
              )
              .join(' or ')
        : _targetReadableByIdExpression(reference, id);
    lines
      ..add(
        "$indent"
        "if ($patchExpression) ? '${field.name}' "
        "and jsonb_typeof($patchExpression -> '${field.name}') <> 'null' "
        'and not ($allowed) then',
      )
      ..add(
        "$indent  raise exception 'Referenced entity access denied' "
        "using errcode = '42501';",
      )
      ..add(
        '$indent'
        'end if;',
      );
  }
  return lines.join('\n');
}

String _workflowMembershipCreateValidationSql(
  EntitySpec spec,
  String patchExpression, {
  required String indent,
}) {
  final membership = spec.workflowMembership;
  if (membership == null) return '';
  return '''${indent}if ($patchExpression ->> '${membership.participant.name}')::uuid = auth.uid() then
$indent  raise exception 'Owner is already a collaborator' using errcode = '22023';
${indent}end if;''';
}

String _postgresType(FieldSpec field) => switch (field.sqlType) {
  SqlType.text => 'text',
  SqlType.uuid => 'uuid',
  SqlType.boolean => 'boolean',
  SqlType.integer => 'bigint',
  SqlType.real => 'double precision',
  SqlType.date => 'date',
  SqlType.timestampWithTimeZone => 'timestamptz',
};

String _jsonCast(String expression, FieldSpec field) {
  return switch (field.sqlType) {
    SqlType.text => "$expression #>> '{}'",
    SqlType.uuid => "($expression #>> '{}')::uuid",
    SqlType.boolean => "($expression #>> '{}')::boolean",
    SqlType.integer => "($expression #>> '{}')::bigint",
    SqlType.real => "($expression #>> '{}')::double precision",
    SqlType.date => "($expression #>> '{}')::date",
    SqlType.timestampWithTimeZone => "($expression #>> '{}')::timestamptz",
  };
}

String _jsonbLiteral(Object? value) {
  final encoded = jsonEncode(value).replaceAll("'", "''");
  return "'$encoded'::jsonb";
}

String _sqlLiteral(Object? value) => switch (value) {
  null => 'null',
  final bool value => value ? 'true' : 'false',
  final num value => value.toString(),
  final String value => "'${value.replaceAll("'", "''")}'",
  _ => throw StateError('Unsupported SQL default: $value'),
};

String _sqlDefaultLiteral(FieldSpec field) =>
    _sqlLiteral(field.persistedDefaultValue);
