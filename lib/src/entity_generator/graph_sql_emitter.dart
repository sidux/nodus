import 'package:nodus/nodus.dart';

import 'model.dart';
import 'sql_emitter.dart';

String emitEntityGraphSupabaseSql(EntityGraphSpec graph) {
  final orderedEntities = _dependencyOrder(graph);
  final graphName = snakeCase(graph.className);
  final functionName = 'pull_${graphName}_graph_changes';
  final inboundEntityTypes = {
    for (final binding in graph.syncBindings)
      if (binding.mode == SyncMode.replicated ||
          binding.mode == SyncMode.imported)
        binding.entity.className,
  };
  final visibilityCases = graph.entities
      .where((entity) => inboundEntityTypes.contains(entity.className))
      .map((entity) {
        if (entity.isActivityEntry) {
          final source = graph.activityTrackings
              .singleWhere(
                (tracking) => tracking.entry.className == entity.className,
              )
              .source;
          final sourceAccess = _activitySourceSelectExpression(
            source,
            'activity.subject_id',
          );
          return "      when '${entity.className}' then (exists (select 1 "
              'from public.${entity.tableName} activity where '
              'activity.${entity.idField.columnName} = changes.entity_id '
              'and ($sourceAccess)))';
        }
        final selectPrincipals = entity.security.grants
            .where((grant) => grant.operation == RlsOperation.select)
            .map((grant) => grant.principal)
            .toSet();
        if (selectPrincipals.contains(RlsPrincipal.authenticated) &&
            entity.syncAuthenticatedReads) {
          return "      when '${entity.className}' then (true)";
        }
        final expressions = <String>['changes.owner_id = auth.uid()'];
        if (selectPrincipals.contains(RlsPrincipal.participant)) {
          expressions.add(
            'public.is_${entity.tableName}_participant(changes.entity_id)',
          );
        }
        if (selectPrincipals.contains(RlsPrincipal.collaborator)) {
          final collaboration = entity.security.collaboration;
          final function = collaboration?.hasAdditionalReadableStates ?? false
              ? 'viewer'
              : 'collaborator';
          expressions.add(
            'public.is_${entity.tableName}_$function(changes.entity_id)',
          );
        }
        if (selectPrincipals.contains(RlsPrincipal.reference)) {
          expressions.add(
            'public.is_${entity.tableName}_reference(changes.entity_id)',
          );
        }
        if (entity.relationshipAccessOperations.contains(RlsOperation.select)) {
          expressions.add(
            'public.is_${entity.tableName}_relationship_select('
            'changes.entity_id)',
          );
        }
        final visibility = expressions.join(' or ');
        return "      when '${entity.className}' then ($visibility)";
      })
      .join('\n');

  final entitiesSql = <String>[];
  final hasOrderedEntity = graph.entities.any(
    (entity) => entity.hasOrderedCapability,
  );
  for (final (index, entity) in orderedEntities.indexed) {
    final activitySource = graph.activityTrackings
        .where((tracking) => tracking.entry.className == entity.className)
        .map((tracking) => tracking.source)
        .firstOrNull;
    entitiesSql.add(
      emitSupabaseSql(
        entity,
        activitySource: activitySource,
        includeSharedTables: index == 0,
        includeOrderScopeTable: index == 0 && hasOrderedEntity,
        includeEntityPull: false,
      ).trim(),
    );
  }
  final referenceAccessSql = _emitReferenceAccessPropagationSql(graph);
  final workflowCollaborationSql = _emitWorkflowCollaborationSql(graph);
  final relationshipAccessSql = _emitRelationshipAccessSql(graph);
  final compositionSql = _emitCompositionSql(graph);

  return '''-- GENERATED FILE. DO NOT EDIT.
-- Source: ${graph.inputImport}
-- Sync target: ${graph.syncTargets.single.wireName}
-- The target descriptor subgraph is the source of truth for this public schema fragment.

${entitiesSql.join('\n\n')}${compositionSql.isEmpty ? '' : '\n\n$compositionSql'}${relationshipAccessSql.isEmpty ? '' : '\n\n$relationshipAccessSql'}${referenceAccessSql.isEmpty ? '' : '\n\n$referenceAccessSql'}${workflowCollaborationSql.isEmpty ? '' : '\n\n$workflowCollaborationSql'}

-- One globally ordered pull contract for this synchronization target.

create or replace function public.$functionName(p_after_sequence bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as \$\$
declare
  page jsonb := '[]'::jsonb;
  page_count integer;
  next_cursor bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'sequence', visible.sequence,
    'entity_type', visible.entity_type,
    'record', visible.record,
    'server_version', visible.server_version,
    'operation_id', visible.operation_id,
    'is_revocation', visible.is_revocation
  ) order by visible.sequence), '[]'::jsonb)
  into page
  from (
    select
      changes.sequence,
      changes.entity_type,
      changes.record,
      changes.server_version,
      changes.operation_id,
      (changes.is_revocation and changes.audience_user_id = auth.uid())
        as is_revocation
    from public.local_entity_changes changes
    where changes.sequence > p_after_sequence
      and (
        (
          changes.audience_user_id is null
          and case changes.entity_type
$visibilityCases
            else false
          end
        )
        or changes.audience_user_id = auth.uid()
      )
    order by changes.sequence
    limit 500
  ) visible;
  page_count := jsonb_array_length(page);
  if page_count = 500 then
    next_cursor := (page -> (page_count - 1) ->> 'sequence')::bigint;
  else
    select coalesce(max(changes.sequence), p_after_sequence)
      into next_cursor
    from public.local_entity_changes changes;
  end if;
  return jsonb_build_object(
    'changes', page,
    'nextSequence', next_cursor,
    'hasMore', page_count = 500
  );
end;
\$\$;

revoke all on function public.$functionName(bigint) from $supabaseApiRoles;
grant execute on function public.$functionName(bigint) to authenticated;
''';
}

String _activitySourceSelectExpression(EntitySpec source, String idExpression) {
  final expressions = source.security.grants
      .where((grant) => grant.operation == RlsOperation.select)
      .map(
        (grant) => switch (grant.principal) {
          RlsPrincipal.owner =>
            'public.is_${source.tableName}_owner($idExpression)',
          RlsPrincipal.participant =>
            'public.is_${source.tableName}_participant($idExpression)',
          RlsPrincipal.collaborator =>
            'public.is_${source.tableName}_${source.security.collaboration?.hasAdditionalReadableStates ?? false ? 'viewer' : 'collaborator'}($idExpression)',
          RlsPrincipal.reference =>
            'public.is_${source.tableName}_reference($idExpression)',
          RlsPrincipal.relationship =>
            'public.is_${source.tableName}_relationship_select($idExpression)',
          RlsPrincipal.authenticated => 'auth.uid() is not null',
        },
      )
      .toSet();
  if (source.relationshipAccessOperations.contains(RlsOperation.select)) {
    expressions.add(
      'public.is_${source.tableName}_relationship_select($idExpression)',
    );
  }
  return expressions.isEmpty ? 'false' : expressions.join(' or ');
}

String _emitCompositionSql(EntityGraphSpec graph) {
  final byTarget = <String, List<(EntitySpec, FieldSpec)>>{};
  for (final aggregate in graph.entities) {
    for (final field in aggregate.fields.where(
      (field) => field.isComposition,
    )) {
      byTarget
          .putIfAbsent(
            field.reference!.targetClassName,
            () => <(EntitySpec, FieldSpec)>[],
          )
          .add((aggregate, field));
    }
  }
  final sections = <String>[];
  for (final entry in byTarget.entries) {
    final component = graph.entities.singleWhere(
      (entity) => entity.className == entry.key,
    );
    final sources = entry.value;
    for (final (aggregate, field) in sources) {
      final base = _sqlAlias(
        '${aggregate.tableName}_${field.columnName}_composition',
      );
      final ownershipChecks = sources
          .map((source) {
            final stored =
                'select 1 from public.${source.$1.tableName} candidate '
                'where candidate.${source.$2.columnName} = new.${field.columnName} '
                'and not (candidate.${source.$1.idField.columnName} = '
                'new.${aggregate.idField.columnName} and '
                '${_sqlLiteral(source.$1.tableName)} = '
                '${_sqlLiteral(aggregate.tableName)} and '
                '${_sqlLiteral(source.$2.columnName)} = '
                '${_sqlLiteral(field.columnName)})';
            if (source.$1.className == aggregate.className &&
                source.$2.name != field.name) {
              return '$stored union all select 1 '
                  'where new.${source.$2.columnName} = new.${field.columnName}';
            }
            return stored;
          })
          .join(' union all ');
      final remainingReferences = sources
          .map(
            (source) =>
                'select 1 from public.${source.$1.tableName} candidate '
                'where candidate.${source.$2.columnName} = '
                'old.${field.columnName}',
          )
          .join(' union all ');
      sections.add(
        '''-- Exclusive aggregate ownership for ${aggregate.className}.${field.name}.

create or replace function public.enforce_$base()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
begin
  if tg_op = 'INSERT' or new.${field.columnName} is distinct from old.${field.columnName} then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(new.${field.columnName}::text, 0)
    );
    if not exists (
      select 1 from public.${component.tableName} component
      where component.${component.idField.columnName} = new.${field.columnName}
        and component.${component.ownerField.columnName} = new.${aggregate.ownerField.columnName}
    ) then
      raise exception 'Composition component owner mismatch' using errcode = '23503';
    end if;
    if exists ($ownershipChecks) then
      raise exception 'Component identity already belongs to an aggregate' using errcode = '23505';
    end if;
  end if;
  return new;
end;
\$\$;

revoke all on function public.enforce_$base() from $supabaseApiRoles;
drop trigger if exists ${base}_enforce on public.${aggregate.tableName};
create trigger ${base}_enforce
before insert or update of ${field.columnName}
on public.${aggregate.tableName}
for each row execute function public.enforce_$base();

create or replace function public.cleanup_$base()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(old.${field.columnName}::text, 0)
  );
  if not exists ($remainingReferences) then
    delete from public.${component.tableName}
    where ${component.idField.columnName} = old.${field.columnName};
  end if;
  return old;
end;
\$\$;

revoke all on function public.cleanup_$base() from $supabaseApiRoles;
drop trigger if exists ${base}_cleanup on public.${aggregate.tableName};
create trigger ${base}_cleanup
after delete on public.${aggregate.tableName}
for each row execute function public.cleanup_$base();''',
      );
    }
  }
  return sections.join('\n\n');
}

String _emitRelationshipAccessSql(EntityGraphSpec graph) {
  final sections = <String>[];
  for (final target in graph.entities.where(
    (entity) => entity.relationshipAccessOperations.isNotEmpty,
  )) {
    for (final operation in target.relationshipAccessOperations) {
      final predicate = _relationshipAccessByUserExpression(
        graph,
        target,
        operation: operation,
        entityId: 'p_id',
        userExpression: 'auth.uid()',
      );
      sections.add(
        '''-- Relationship-derived ${operation.name} access for ${target.className}.

create or replace function public.is_${target.tableName}_relationship_${operation.name}(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as \$\$
  select $predicate;
\$\$;

revoke all on function public.is_${target.tableName}_relationship_${operation.name}(uuid) from $supabaseApiRoles;
grant execute on function public.is_${target.tableName}_relationship_${operation.name}(uuid) to authenticated;''',
      );
    }
    final readable = _readableByUserExpression(
      graph,
      target,
      rowAlias: 'target_row',
      userExpression: 'p_user_id',
    );
    final propagatesReferenceAccess = _hasReferenceAccessDependents(
      graph,
      target,
    );
    final publishFunction = 'publish_${target.tableName}_relationship_access';
    sections.add(
      '''-- Ordered snapshots and revocations for relationship-derived ${target.className} access.

create or replace function public.$publishFunction(
  p_target_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  target_row public.${target.tableName};
begin
  select * into target_row from public.${target.tableName}
  where ${target.idField.columnName} = p_target_id;
  if not found then return; end if;

  delete from public.local_entity_changes
  where entity_type = '${target.className}'
    and entity_id = p_target_id
    and audience_user_id = p_user_id;
  insert into public.local_entity_changes (
    entity_type, entity_id, owner_id, server_version,
    operation_id, audience_user_id, is_revocation, record
  ) values (
    '${target.className}',
    target_row.${target.idField.columnName},
    target_row.${target.ownerField.columnName},
    target_row.${target.serverVersionField.columnName},
    nullif(current_setting('app.operation_id', true), '')::uuid,
    p_user_id,
    not ($readable),
    to_jsonb(target_row)
  );
${propagatesReferenceAccess ? '  perform public.publish_${target.tableName}_reference_access(\n    p_target_id,\n    p_user_id\n  );' : ''}
  return;
end;
\$\$;

revoke all on function public.$publishFunction(uuid, uuid) from $supabaseApiRoles;''',
    );
  }
  for (final relationship in graph.entities) {
    for (final targetField in relationship.accessTargetFields) {
      final destinations = _accessTargetDestinations(graph, targetField);
      final functionName =
          'publish_${relationship.tableName}_${targetField.columnName}_access';
      final watchedColumns = <String>{
        targetField.columnName,
        for (final source in relationship.accessReferenceFields)
          source.columnName,
        for (final participant in relationship.participantFields)
          participant.columnName,
        if (relationship.activeField case final field?) field.columnName,
        if (targetField.accessTargetActiveStates.isNotEmpty)
          relationship.fields
              .singleWhere((field) => field.name == 'status')
              .columnName,
        if (relationship.deletedAtField case final field?) field.columnName,
      }.join(', ');
      final oldAudience = _relationshipAudienceSelect(
        graph,
        relationship,
        rowAlias: 'old',
      );
      final newAudience = _relationshipAudienceSelect(
        graph,
        relationship,
        rowAlias: 'new',
      );
      String publications(String rowAlias) => destinations
          .map(
            (destination) =>
                '      perform public.publish_${destination.target.tableName}_relationship_access(\n'
                '        ${_accessTargetIdExpression(graph, targetField, destination, rowAlias: rowAlias)},\n'
                '        audience_user_id\n'
                '      );',
          )
          .join('\n');
      sections.add(
        '''-- Access publication for ${relationship.className}.${targetField.name}.

create or replace function public.$functionName()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  audience_user_id uuid;
begin
  if tg_op <> 'INSERT' then
    for audience_user_id in $oldAudience loop
${publications('old')}
    end loop;
  end if;
  if tg_op <> 'DELETE' then
    for audience_user_id in $newAudience loop
${publications('new')}
    end loop;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
\$\$;

revoke all on function public.$functionName() from $supabaseApiRoles;
drop trigger if exists ${relationship.tableName}_${targetField.columnName}_publish_access
on public.${relationship.tableName};
create trigger ${relationship.tableName}_${targetField.columnName}_publish_access
after insert or update of $watchedColumns or delete
on public.${relationship.tableName}
for each row execute function public.$functionName();''',
      );
    }
  }
  return sections.join('\n\n');
}

typedef _AccessTargetDestination = ({
  EntitySpec target,
  List<RlsOperation> operations,
  bool throughBridge,
});

List<_AccessTargetDestination> _accessTargetDestinations(
  EntityGraphSpec graph,
  FieldSpec field,
) {
  final destinations = <_AccessTargetDestination>[];
  if (field.accessTargetThroughColumnName != null) {
    destinations.add((
      target: graph.entities.singleWhere(
        (entity) => entity.className == field.reference!.targetClassName,
      ),
      operations: const [RlsOperation.select],
      throughBridge: false,
    ));
  }
  destinations.add((
    target: graph.entities.singleWhere(
      (entity) => entity.className == field.accessTargetClassName,
    ),
    operations: field.accessTargetOperations,
    throughBridge: field.accessTargetThroughColumnName != null,
  ));
  return destinations;
}

String _accessTargetMatchExpression(
  EntityGraphSpec graph,
  FieldSpec field,
  _AccessTargetDestination destination, {
  required String rowAlias,
  required String entityId,
}) {
  if (!destination.throughBridge) {
    return '$rowAlias.${field.columnName} = $entityId';
  }
  final bridge = graph.entities.singleWhere(
    (entity) => entity.className == field.reference!.targetClassName,
  );
  return 'exists (select 1 from public.${bridge.tableName} access_bridge '
      'where access_bridge.${bridge.idField.columnName} = '
      '$rowAlias.${field.columnName} and '
      'access_bridge.${field.accessTargetThroughColumnName} = $entityId)';
}

String _accessTargetIdExpression(
  EntityGraphSpec graph,
  FieldSpec field,
  _AccessTargetDestination destination, {
  required String rowAlias,
}) {
  if (!destination.throughBridge) return '$rowAlias.${field.columnName}';
  final bridge = graph.entities.singleWhere(
    (entity) => entity.className == field.reference!.targetClassName,
  );
  return '(select access_bridge.${field.accessTargetThroughColumnName} from '
      'public.${bridge.tableName} access_bridge where '
      'access_bridge.${bridge.idField.columnName} = '
      '$rowAlias.${field.columnName})';
}

String _relationshipAudienceSelect(
  EntityGraphSpec graph,
  EntitySpec relationship, {
  required String rowAlias,
}) {
  final candidates = <String>[];
  if (relationship.accessTargetFields.any((field) => field.isComposition)) {
    candidates.addAll(
      _entityAudienceCandidates(
        graph,
        relationship,
        entityId: '$rowAlias.${relationship.idField.columnName}',
        aliasPrefix: _sqlAlias('audience_${relationship.tableName}_self'),
      ),
    );
  }
  for (final participant in relationship.participantFields) {
    candidates.add('select $rowAlias.${participant.columnName} as user_id');
  }
  for (final (sourceIndex, source)
      in relationship.accessReferenceFields.indexed) {
    final target = graph.entities.singleWhere(
      (entity) => entity.className == source.reference!.targetClassName,
    );
    final sourceId = '$rowAlias.${source.columnName}';
    candidates.addAll(
      _entityAudienceCandidates(
        graph,
        target,
        entityId: sourceId,
        aliasPrefix: _sqlAlias(
          'audience_${relationship.tableName}_${sourceIndex + 1}',
        ),
      ),
    );
  }
  if (candidates.isEmpty) {
    throw StateError(
      '${relationship.className} has no finite access-target audience.',
    );
  }
  final readable = _relationshipAudienceByUserExpression(
    graph,
    relationship,
    rowAlias: rowAlias,
    userExpression: 'candidate.user_id',
  );
  return '''select distinct candidate.user_id
    from (${candidates.join(' union ')}) candidate
    where candidate.user_id is not null and ($readable)''';
}

String _relationshipAudienceByUserExpression(
  EntityGraphSpec graph,
  EntitySpec relationship, {
  required String rowAlias,
  required String userExpression,
}) {
  final expressions = <String>{
    for (final participant in relationship.participantFields)
      '$rowAlias.${participant.columnName} = $userExpression',
  };
  if (relationship.accessTargetFields.any((field) => field.isComposition)) {
    expressions.add(
      _readableByUserExpression(
        graph,
        relationship,
        rowAlias: rowAlias,
        userExpression: userExpression,
      ),
    );
  }
  if (relationship.accessReferenceFields.isNotEmpty) {
    expressions.add(
      _referencesByUserExpression(
        graph,
        relationship,
        rowAlias: rowAlias,
        userExpression: userExpression,
      ),
    );
  }
  if (expressions.isEmpty) {
    throw StateError(
      '${relationship.className} has no finite access-target audience.',
    );
  }
  return expressions.length == 1
      ? expressions.single
      : '(${expressions.join(' or ')})';
}

List<String> _relationshipActivePredicates(
  EntitySpec relationship,
  FieldSpec accessTarget, {
  required String rowAlias,
}) => [
  if (accessTarget.accessTargetActiveStates.isNotEmpty)
    '$rowAlias.${relationship.fields.singleWhere((field) => field.name == 'status').columnName} '
        'in (${accessTarget.accessTargetActiveStates.map((value) => _sqlLiteral(snakeCase(value))).join(', ')})'
  else if (relationship.activeField case final active?)
    '$rowAlias.${active.columnName}',
  if (relationship.deletedAtField case final deletedAt?)
    '$rowAlias.${deletedAt.columnName} is null',
];

List<String> _entityAudienceCandidates(
  EntityGraphSpec graph,
  EntitySpec target, {
  required String entityId,
  required String aliasPrefix,
}) {
  final candidates = <String>[];
  final targetAlias = _sqlAlias('${aliasPrefix}_${target.tableName}');
  final principals = target.security.grants
      .where((grant) => grant.operation == RlsOperation.select)
      .map((grant) => grant.principal)
      .toSet();
  if (principals.contains(RlsPrincipal.owner)) {
    candidates.add(
      'select $targetAlias.${target.ownerField.columnName} as user_id '
      'from public.${target.tableName} $targetAlias where '
      '$targetAlias.${target.idField.columnName} = $entityId',
    );
  }
  if (principals.contains(RlsPrincipal.participant)) {
    for (final participant in target.participantFields) {
      candidates.add(
        'select $targetAlias.${participant.columnName} as user_id '
        'from public.${target.tableName} $targetAlias where '
        '$targetAlias.${target.idField.columnName} = $entityId',
      );
    }
  }
  if (principals.contains(RlsPrincipal.collaborator)) {
    final collaboration = target.security.collaboration!;
    final memberAlias = _sqlAlias('${aliasPrefix}_member');
    if (collaboration.isDirect) {
      candidates.add(
        'select $memberAlias.${collaboration.userForeignKey} as user_id '
        'from public.${collaboration.membershipTable} $memberAlias where '
        '$memberAlias.${collaboration.entityForeignKey} = $entityId and '
        '$memberAlias.${collaboration.activeField}',
      );
    } else {
      final membership = graph.entities.singleWhere(
        (entity) => entity.tableName == collaboration.membershipTable,
      );
      final workflow = membership.workflowMembership!;
      candidates.add(
        'select $memberAlias.${workflow.participant.columnName} as user_id '
        'from public.${membership.tableName} $memberAlias where '
        '$memberAlias.${workflow.targetReference.columnName} = $entityId '
        'and $memberAlias.${workflow.status.columnName} = '
        '${_sqlLiteral(collaboration.acceptedValue!)} '
        'and $memberAlias.${membership.deletedAtField!.columnName} is null',
      );
    }
  }
  if (principals.contains(RlsPrincipal.authenticated) ||
      principals.contains(RlsPrincipal.reference)) {
    throw StateError(
      '${target.className} does not have a finite directly enumerable '
      'relationship-access audience.',
    );
  }

  var pathIndex = 0;
  for (final relationship in graph.entities) {
    for (final accessTarget in relationship.accessTargetFields) {
      for (final destination in _accessTargetDestinations(
        graph,
        accessTarget,
      )) {
        if (destination.target.className != target.className ||
            !destination.operations.contains(RlsOperation.select)) {
          continue;
        }
        final relationshipAlias = _sqlAlias(
          '${aliasPrefix}_path_${++pathIndex}_${relationship.tableName}',
        );
        final active = _relationshipActivePredicates(
          relationship,
          accessTarget,
          rowAlias: relationshipAlias,
        );
        final targetMatch = _accessTargetMatchExpression(
          graph,
          accessTarget,
          destination,
          rowAlias: relationshipAlias,
          entityId: entityId,
        );
        for (final participant in relationship.participantFields) {
          candidates.add(
            'select $relationshipAlias.${participant.columnName} as user_id '
            'from public.${relationship.tableName} $relationshipAlias where '
            '$targetMatch'
            '${active.isEmpty ? '' : ' and ${active.join(' and ')}'}',
          );
        }
        if (accessTarget.isComposition) {
          final upstreamCandidates = _entityAudienceCandidates(
            graph,
            relationship,
            entityId: '$relationshipAlias.${relationship.idField.columnName}',
            aliasPrefix: _sqlAlias('${relationshipAlias}_composition'),
          );
          for (final upstream in upstreamCandidates) {
            candidates.add(
              'select upstream.user_id from '
              'public.${relationship.tableName} $relationshipAlias '
              'cross join lateral ($upstream) upstream where '
              '$targetMatch'
              '${active.isEmpty ? '' : ' and ${active.join(' and ')}'}',
            );
          }
        }
        for (final (sourceIndex, source)
            in relationship.accessReferenceFields.indexed) {
          final sourceTarget = graph.entities.singleWhere(
            (entity) => entity.className == source.reference!.targetClassName,
          );
          final upstreamCandidates = _entityAudienceCandidates(
            graph,
            sourceTarget,
            entityId: '$relationshipAlias.${source.columnName}',
            aliasPrefix: _sqlAlias(
              '${relationshipAlias}_source_${sourceIndex + 1}',
            ),
          );
          for (final upstream in upstreamCandidates) {
            candidates.add(
              'select upstream.user_id from '
              'public.${relationship.tableName} $relationshipAlias '
              'cross join lateral ($upstream) upstream where '
              '$targetMatch'
              '${active.isEmpty ? '' : ' and ${active.join(' and ')}'}',
            );
          }
        }
      }
    }
  }
  return candidates;
}

/// PostgreSQL silently truncates identifiers after 63 bytes. Deep access DAGs
/// can otherwise collapse distinct aliases to the same identifier and produce
/// invalid or, worse, ambiguous SQL. Generated names are ASCII, so characters
/// and bytes have identical lengths here.
String _sqlAlias(String value) {
  const maxIdentifierLength = 63;
  if (value.length <= maxIdentifierLength) return value;

  final mask = (BigInt.one << 64) - BigInt.one;
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  for (final codeUnit in value.codeUnits) {
    hash = ((hash ^ BigInt.from(codeUnit)) * prime) & mask;
  }
  final suffix = hash.toRadixString(16).padLeft(16, '0');
  final prefixLength = maxIdentifierLength - suffix.length - 1;
  return '${value.substring(0, prefixLength)}_$suffix';
}

String _relationshipAccessByUserExpression(
  EntityGraphSpec graph,
  EntitySpec target, {
  required RlsOperation operation,
  required String entityId,
  required String userExpression,
}) {
  final paths = <String>[];
  var index = 0;
  for (final relationship in graph.entities) {
    for (final field in relationship.accessTargetFields) {
      for (final destination in _accessTargetDestinations(graph, field)) {
        if (destination.target.className != target.className ||
            !destination.operations.contains(operation)) {
          continue;
        }
        final alias = 'access_path_${index++}';
        final active = _relationshipActivePredicates(
          relationship,
          field,
          rowAlias: alias,
        );
        final sourceAccess = _relationshipAudienceByUserExpression(
          graph,
          relationship,
          rowAlias: alias,
          userExpression: userExpression,
        );
        final targetMatch = _accessTargetMatchExpression(
          graph,
          field,
          destination,
          rowAlias: alias,
          entityId: entityId,
        );
        paths.add(
          'exists (select 1 from public.${relationship.tableName} $alias '
          'where $targetMatch'
          '${active.isEmpty ? '' : ' and ${active.join(' and ')}'} '
          'and ($sourceAccess))',
        );
      }
    }
  }
  if (paths.isEmpty) {
    throw StateError(
      'Missing relationship access path for ${target.className} '
      '${operation.name}.',
    );
  }
  return paths.join(' or ');
}

String _emitWorkflowCollaborationSql(EntityGraphSpec graph) {
  final sections = <String>[];
  for (final target in graph.entities.where(
    (entity) => entity.security.collaboration?.isWorkflow ?? false,
  )) {
    final collaboration = target.security.collaboration!;
    final membership = graph.entities.singleWhere(
      (entity) => entity.tableName == collaboration.membershipTable,
    );
    final workflow = membership.workflowMembership!;
    final accepted = _sqlLiteral(collaboration.acceptedValue!);
    final deletedAt = membership.fields.singleWhere(
      (field) => field.name == EntityConventions.deletedAtFieldName,
    );
    final functionName = 'publish_${membership.tableName}_access';
    final propagatesReferenceAccess = graph.entities.any(
      (entity) => entity.accessReferenceFields.any(
        (field) => field.reference!.targetClassName == target.className,
      ),
    );
    final conditionalReferencePropagation = propagatesReferenceAccess
        ? '''  if was_active is distinct from is_active then
    perform public.publish_${target.tableName}_reference_access(
      new.${workflow.targetReference.columnName},
      new.${workflow.participant.columnName}
    );
  end if;'''
        : '';
    if (collaboration.hasAdditionalReadableStates) {
      final readable = collaboration.readableValues.map(_sqlLiteral).join(', ');
      sections.add('''-- Entity-backed collaboration for ${target.className}.

create or replace function public.is_${target.tableName}_collaborator(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as \$\$
  select exists (
    select 1 from public.${membership.tableName} member
    where member.${workflow.targetReference.columnName} = p_id
      and member.${workflow.participant.columnName} = auth.uid()
      and member.${workflow.status.columnName} = $accepted
      and member.${deletedAt.columnName} is null
  );
\$\$;

create or replace function public.is_${target.tableName}_viewer(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as \$\$
  select exists (
    select 1 from public.${membership.tableName} member
    where member.${workflow.targetReference.columnName} = p_id
      and member.${workflow.participant.columnName} = auth.uid()
      and member.${workflow.status.columnName} in ($readable)
      and member.${deletedAt.columnName} is null
  );
\$\$;

revoke all on function public.is_${target.tableName}_collaborator(uuid) from $supabaseApiRoles;
revoke all on function public.is_${target.tableName}_viewer(uuid) from $supabaseApiRoles;
grant execute on function public.is_${target.tableName}_collaborator(uuid) to authenticated;
grant execute on function public.is_${target.tableName}_viewer(uuid) to authenticated;

create or replace function public.$functionName()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  target_row public.${target.tableName};
  was_active boolean := false;
  is_active boolean;
  was_visible boolean := false;
  is_visible boolean;
begin
  if tg_op = 'UPDATE' then
    was_active := old.${workflow.status.columnName} = $accepted
      and old.${deletedAt.columnName} is null;
    was_visible := old.${workflow.status.columnName} in ($readable)
      and old.${deletedAt.columnName} is null;
  end if;
  is_active := new.${workflow.status.columnName} = $accepted
    and new.${deletedAt.columnName} is null;
  is_visible := new.${workflow.status.columnName} in ($readable)
    and new.${deletedAt.columnName} is null;
  if was_active = is_active and was_visible = is_visible then
    return new;
  end if;

  if was_visible is distinct from is_visible then
    select * into target_row from public.${target.tableName}
    where ${target.idField.columnName} = new.${workflow.targetReference.columnName};
    if not found then
      raise exception 'Collaboration target not found' using errcode = 'P0001';
    end if;

    delete from public.local_entity_changes
    where entity_type = '${target.className}'
      and entity_id = target_row.${target.idField.columnName}
      and audience_user_id = new.${workflow.participant.columnName};
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
      '${target.className}',
      target_row.${target.idField.columnName},
      target_row.${target.ownerField.columnName},
      target_row.${target.serverVersionField.columnName},
      nullif(current_setting('app.operation_id', true), '')::uuid,
      new.${workflow.participant.columnName},
      not is_visible,
      to_jsonb(target_row)
    );
  end if;
$conditionalReferencePropagation
  return new;
end;
\$\$;

revoke all on function public.$functionName() from $supabaseApiRoles;
drop trigger if exists ${membership.tableName}_publish_access on public.${membership.tableName};
create trigger ${membership.tableName}_publish_access
after insert or update of ${workflow.status.columnName}, ${deletedAt.columnName}
on public.${membership.tableName}
for each row execute function public.$functionName();''');
      continue;
    }
    sections.add('''-- Entity-backed collaboration for ${target.className}.

create or replace function public.is_${target.tableName}_collaborator(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as \$\$
  select exists (
    select 1 from public.${membership.tableName} member
    where member.${workflow.targetReference.columnName} = p_id
      and member.${workflow.participant.columnName} = auth.uid()
      and member.${workflow.status.columnName} = $accepted
      and member.${deletedAt.columnName} is null
  );
\$\$;

revoke all on function public.is_${target.tableName}_collaborator(uuid) from $supabaseApiRoles;
grant execute on function public.is_${target.tableName}_collaborator(uuid) to authenticated;

create or replace function public.$functionName()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  target_row public.${target.tableName};
  was_active boolean := false;
  is_active boolean;
begin
  if tg_op = 'UPDATE' then
    was_active := old.${workflow.status.columnName} = $accepted
      and old.${deletedAt.columnName} is null;
  end if;
  is_active := new.${workflow.status.columnName} = $accepted
    and new.${deletedAt.columnName} is null;
  if was_active = is_active then
    return new;
  end if;

  select * into target_row from public.${target.tableName}
  where ${target.idField.columnName} = new.${workflow.targetReference.columnName};
  if not found then
    raise exception 'Collaboration target not found' using errcode = 'P0001';
  end if;

  delete from public.local_entity_changes
  where entity_type = '${target.className}'
    and entity_id = target_row.${target.idField.columnName}
    and audience_user_id = new.${workflow.participant.columnName};
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
    '${target.className}',
    target_row.${target.idField.columnName},
    target_row.${target.ownerField.columnName},
    target_row.${target.serverVersionField.columnName},
    nullif(current_setting('app.operation_id', true), '')::uuid,
    new.${workflow.participant.columnName},
    not is_active,
    to_jsonb(target_row)
  );
${propagatesReferenceAccess ? '  perform public.publish_${target.tableName}_reference_access(\n    new.${workflow.targetReference.columnName},\n    new.${workflow.participant.columnName}\n  );' : ''}
  return new;
end;
\$\$;

revoke all on function public.$functionName() from $supabaseApiRoles;
drop trigger if exists ${membership.tableName}_publish_access on public.${membership.tableName};
create trigger ${membership.tableName}_publish_access
after insert or update of ${workflow.status.columnName}, ${deletedAt.columnName}
on public.${membership.tableName}
for each row execute function public.$functionName();''');
  }
  return sections.join('\n\n');
}

String _emitReferenceAccessPropagationSql(EntityGraphSpec graph) {
  final sections = <String>[];
  for (final target in graph.entities) {
    final dependents = <(EntitySpec, List<FieldSpec>)>[];
    for (final entity in graph.entities) {
      final fields = entity.accessReferenceFields
          .where(
            (field) => field.reference!.targetClassName == target.className,
          )
          .toList(growable: false);
      if (fields.isNotEmpty) dependents.add((entity, fields));
    }
    if (dependents.isEmpty ||
        (target.security.collaboration == null &&
            target.relationshipAccessOperations.isEmpty)) {
      continue;
    }

    final functionName = 'publish_${target.tableName}_reference_access';
    final body = StringBuffer();
    for (final (dependent, fields) in dependents) {
      final affected = fields
          .map((field) => 'entity.${field.columnName} = p_target_id')
          .join(' or ');
      final readable = _readableByUserExpression(
        graph,
        dependent,
        rowAlias: 'entity',
        userExpression: 'p_user_id',
      );
      body
        ..writeln('  delete from public.local_entity_changes changes')
        ..writeln('  using public.${dependent.tableName} entity')
        ..writeln("  where changes.entity_type = '${dependent.className}'")
        ..writeln(
          '    and changes.entity_id = entity.${dependent.idField.columnName}',
        )
        ..writeln('    and changes.audience_user_id = p_user_id')
        ..writeln('    and ($affected);')
        ..writeln('  insert into public.local_entity_changes (')
        ..writeln('    entity_type, entity_id, owner_id, server_version,')
        ..writeln('    operation_id, audience_user_id, is_revocation, record')
        ..writeln('  )')
        ..writeln('  select')
        ..writeln("    '${dependent.className}',")
        ..writeln('    entity.${dependent.idField.columnName},')
        ..writeln('    entity.${dependent.ownerField.columnName},')
        ..writeln('    entity.${dependent.serverVersionField.columnName},')
        ..writeln(
          "    nullif(current_setting('app.operation_id', true), '')::uuid,",
        )
        ..writeln('    p_user_id,')
        ..writeln('    not ($readable),')
        ..writeln('    to_jsonb(entity)')
        ..writeln('  from public.${dependent.tableName} entity')
        ..writeln('  where $affected;');
      for (final accessTarget in dependent.accessTargetFields) {
        for (final destination in _accessTargetDestinations(
          graph,
          accessTarget,
        )) {
          body
            ..writeln(
              '  perform public.publish_${destination.target.tableName}_relationship_access(',
            )
            ..writeln(
              '    ${_accessTargetIdExpression(graph, accessTarget, destination, rowAlias: 'entity')}, p_user_id',
            )
            ..writeln('  )')
            ..writeln('  from public.${dependent.tableName} entity')
            ..writeln('  where $affected;');
        }
      }
    }
    final directTrigger = target.security.collaboration?.isDirect == true
        ? _emitDirectReferenceAccessTrigger(target, functionName)
        : '';
    sections.add(
      '''-- Reference-derived access propagation for ${target.className}.

create or replace function public.$functionName(
  p_target_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as \$\$
begin
$body  return;
end;
\$\$;

revoke all on function public.$functionName(uuid, uuid) from $supabaseApiRoles;$directTrigger''',
    );
  }
  return sections.join('\n\n');
}

bool _hasReferenceAccessDependents(EntityGraphSpec graph, EntitySpec target) =>
    graph.entities.any(
      (entity) => entity.accessReferenceFields.any(
        (field) => field.reference!.targetClassName == target.className,
      ),
    );

String _emitDirectReferenceAccessTrigger(
  EntitySpec target,
  String publicationFunction,
) {
  final collaboration = target.security.collaboration!;
  final triggerFunction =
      'publish_${collaboration.membershipTable}_reference_access';
  return '''

create or replace function public.$triggerFunction()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  target_id uuid;
  user_id uuid;
  was_active boolean := false;
  is_active boolean := false;
begin
  if tg_op <> 'INSERT' then
    was_active := old.${collaboration.activeField};
  end if;
  if tg_op <> 'DELETE' then
    is_active := new.${collaboration.activeField};
  end if;
  if was_active = is_active then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  target_id := case when tg_op = 'DELETE'
    then old.${collaboration.entityForeignKey}
    else new.${collaboration.entityForeignKey} end;
  user_id := case when tg_op = 'DELETE'
    then old.${collaboration.userForeignKey}
    else new.${collaboration.userForeignKey} end;
  perform public.$publicationFunction(target_id, user_id);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
\$\$;

revoke all on function public.$triggerFunction() from $supabaseApiRoles;
drop trigger if exists ${collaboration.membershipTable}_publish_reference_access
on public.${collaboration.membershipTable};
create trigger ${collaboration.membershipTable}_publish_reference_access
after insert or update of ${collaboration.activeField} or delete
on public.${collaboration.membershipTable}
for each row execute function public.$triggerFunction();''';
}

String _readableByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String rowAlias,
  required String userExpression,
}) {
  final expressions = entity.security.grants
      .where((grant) => grant.operation == RlsOperation.select)
      .map(
        (grant) => _principalByUserExpression(
          graph,
          entity,
          grant.principal,
          rowAlias: rowAlias,
          userExpression: userExpression,
        ),
      )
      .toSet();
  if (entity.relationshipAccessOperations.contains(RlsOperation.select)) {
    expressions.add(
      _relationshipAccessByUserExpression(
        graph,
        entity,
        operation: RlsOperation.select,
        entityId: '$rowAlias.${entity.idField.columnName}',
        userExpression: userExpression,
      ),
    );
  }
  return expressions.isEmpty ? 'false' : expressions.join(' or ');
}

String _principalByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity,
  RlsPrincipal principal, {
  required String rowAlias,
  required String userExpression,
}) => switch (principal) {
  RlsPrincipal.owner =>
    '$rowAlias.${entity.ownerField.columnName} = $userExpression',
  RlsPrincipal.participant =>
    entity.participantFields
        .map((field) => '$rowAlias.${field.columnName} = $userExpression')
        .join(' or '),
  RlsPrincipal.collaborator => _collaboratorByUserExpression(
    graph,
    entity,
    entityId: '$rowAlias.${entity.idField.columnName}',
    userExpression: userExpression,
  ),
  RlsPrincipal.reference => _referencesByUserExpression(
    graph,
    entity,
    rowAlias: rowAlias,
    userExpression: userExpression,
  ),
  RlsPrincipal.relationship => _relationshipAccessByUserExpression(
    graph,
    entity,
    operation: RlsOperation.select,
    entityId: '$rowAlias.${entity.idField.columnName}',
    userExpression: userExpression,
  ),
  RlsPrincipal.authenticated => '$userExpression is not null',
};

String _collaboratorByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String entityId,
  required String userExpression,
}) {
  final collaboration = entity.security.collaboration;
  if (collaboration == null) return 'false';
  if (collaboration.isDirect) {
    return 'exists (select 1 from public.${collaboration.membershipTable} '
        'member where member.${collaboration.entityForeignKey} = $entityId '
        'and member.${collaboration.userForeignKey} = $userExpression '
        'and member.${collaboration.activeField})';
  }
  final membership = graph.entities.singleWhere(
    (candidate) => candidate.tableName == collaboration.membershipTable,
  );
  final workflow = membership.workflowMembership!;
  final deletedAt = membership.fields.singleWhere(
    (field) => field.name == EntityConventions.deletedAtFieldName,
  );
  return 'exists (select 1 from public.${membership.tableName} member '
      'where member.${workflow.targetReference.columnName} = $entityId '
      'and member.${workflow.participant.columnName} = $userExpression '
      'and member.${workflow.status.columnName} = '
      '${_sqlLiteral(collaboration.acceptedValue!)} '
      'and member.${deletedAt.columnName} is null)';
}

String _referencesByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String rowAlias,
  required String userExpression,
}) {
  final byClass = {
    for (final candidate in graph.entities) candidate.className: candidate,
  };
  final access = entity.accessReferenceGroups
      .map((group) {
        final expression = group
            .map((field) {
              final target = byClass[field.reference!.targetClassName]!;
              final targetAlias = 'access_${field.columnName}';
              final readable = _readableByUserExpression(
                graph,
                target,
                rowAlias: targetAlias,
                userExpression: userExpression,
              );
              return 'exists (select 1 from public.${target.tableName} '
                  '$targetAlias where '
                  '$targetAlias.${target.idField.columnName} = '
                  '$rowAlias.${field.columnName} and ($readable))';
            })
            .join(' or ');
        return group.length == 1 ? expression : '($expression)';
      })
      .join(' and ');
  final ownershipReferences = entity.ownershipReferenceFields;
  if (ownershipReferences.isEmpty) return access;
  final ownership = ownershipReferences
      .map((ownershipReference) {
        final target = byClass[ownershipReference.reference!.targetClassName]!;
        final reference = ownershipReference.reference!;
        final equality =
            '$rowAlias.${entity.ownerField.columnName} = '
            '(select ownership_target.${reference.ownershipSourceColumnName} from '
            'public.${target.tableName} ownership_target where '
            'ownership_target.${target.idField.columnName} = '
            '$rowAlias.${ownershipReference.columnName})';
        return ownershipReference.nullable
            ? '($rowAlias.${ownershipReference.columnName} is not null and '
                  '$equality)'
            : '($equality)';
      })
      .join(' or ');
  return '($access) and (${ownershipReferences.length == 1 ? ownership : '($ownership)'})';
}

String _sqlLiteral(String value) => "'${value.replaceAll("'", "''")}'";

List<EntitySpec> _dependencyOrder(EntityGraphSpec graph) {
  final byClass = {
    for (final entity in graph.entities) entity.className: entity,
  };
  final visiting = <EntitySpec>{};
  final visited = <EntitySpec>{};
  final ordered = <EntitySpec>[];

  void visit(EntitySpec entity) {
    if (visited.contains(entity)) return;
    if (!visiting.add(entity)) {
      throw StateError(
        'Cyclic entity references cannot be emitted as inline PostgreSQL '
        'foreign keys or independently pushed creates.',
      );
    }
    final activitySubject = entity.activitySubjectClassName;
    if (activitySubject != null && activitySubject != entity.className) {
      visit(byClass[activitySubject]!);
    }
    for (final field in entity.fields) {
      final target = field.reference?.targetClassName;
      if (target != null && target != entity.className) {
        visit(byClass[target]!);
      }
    }
    visiting.remove(entity);
    visited.add(entity);
    ordered.add(entity);
  }

  for (final entity in graph.entities) {
    visit(entity);
  }
  return ordered;
}
