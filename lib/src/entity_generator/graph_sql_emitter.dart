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
  final inboundEntities = graph.entities
      .where((entity) => inboundEntityTypes.contains(entity.className))
      .toList(growable: false);
  // Every account may read these, so their changes are not addressed to
  // anyone in particular.
  final broadcastTypes = inboundEntities
      .where(
        (entity) =>
            !entity.isActivityEntry &&
            entity.syncAuthenticatedReads &&
            entity.security.grants.any(
              (grant) =>
                  grant.operation == RlsOperation.select &&
                  grant.principal == RlsPrincipal.authenticated,
            ),
      )
      .map((entity) => _sqlLiteral(entity.className))
      .toList(growable: false);
  final recipientCases = inboundEntities
      .where(
        (entity) => !broadcastTypes.contains(_sqlLiteral(entity.className)),
      )
      .map((entity) => _changeRecipientsCase(graph, entity))
      .join('\n');
  final recipientsFunction = '${graphName}_change_recipients';
  final addressedChanges = broadcastTypes.isEmpty
      ? 'select recipient.sequence from public.local_entity_change_recipients '
            'recipient where recipient.user_id = auth.uid() '
            'and recipient.sequence > p_after_sequence'
      : 'select recipient.sequence from public.local_entity_change_recipients '
            'recipient where recipient.user_id = auth.uid() '
            'and recipient.sequence > p_after_sequence\n'
            '      union\n'
            '      select broadcast.sequence from public.local_entity_changes '
            'broadcast where broadcast.entity_type in '
            '(${broadcastTypes.join(', ')}) '
            'and broadcast.audience_user_id is null '
            'and broadcast.sequence > p_after_sequence';

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
        activeRelationship: graph.relationships
            .where((relationship) => relationship.linkEntity == entity)
            .firstOrNull,
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
  final principalRetirementSql = _emitPrincipalRetirementSql(graph);

  return '''-- GENERATED FILE. DO NOT EDIT.
-- Source: ${graph.inputImport}
-- Sync target: ${graph.syncTargets.single.wireName}
-- The target descriptor subgraph is the source of truth for this public schema fragment.

${entitiesSql.join('\n\n')}${compositionSql.isEmpty ? '' : '\n\n$compositionSql'}${relationshipAccessSql.isEmpty ? '' : '\n\n$relationshipAccessSql'}${referenceAccessSql.isEmpty ? '' : '\n\n$referenceAccessSql'}${workflowCollaborationSql.isEmpty ? '' : '\n\n$workflowCollaborationSql'}

-- Who may pull each change, decided once when it is recorded. Access granted
-- later arrives as its own addressed snapshot, so a change's recipients are
-- exactly the accounts that may read the entity at that moment.

create or replace function public.$recipientsFunction(
  p_entity_type text,
  p_entity_id uuid,
  p_owner_id uuid
) returns table (user_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as \$\$
begin
  case p_entity_type
$recipientCases
    else
      return;
  end case;
end;
\$\$;

revoke all on function public.$recipientsFunction(text, uuid, uuid) from $supabaseApiRoles;

create or replace function public.address_${graphName}_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
begin
  -- Accounts removed in the same transaction have nothing left to pull, and
  -- must not make the change itself fail.
  if new.audience_user_id is not null then
    insert into public.local_entity_change_recipients (user_id, sequence)
    select account.id, new.sequence
    from auth.users account
    where account.id = new.audience_user_id
    on conflict do nothing;
  else
    insert into public.local_entity_change_recipients (user_id, sequence)
    select distinct account.id, new.sequence
    from public.$recipientsFunction(
      new.entity_type,
      new.entity_id,
      new.owner_id
    ) recipient
    join auth.users account on account.id = recipient.user_id
    on conflict do nothing;
  end if;
  return null;
end;
\$\$;

revoke all on function public.address_${graphName}_change() from $supabaseApiRoles;
drop trigger if exists local_entity_changes_address_$graphName on public.local_entity_changes;
create trigger local_entity_changes_address_$graphName
after insert on public.local_entity_changes
for each row execute function public.address_${graphName}_change();

-- One globally ordered pull contract for this synchronization target. It reads
-- only the changes addressed to the caller, by index, in sequence order.

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
    from (
      $addressedChanges
      order by 1
      limit 500
    ) addressed
    join public.local_entity_changes changes
      on changes.sequence = addressed.sequence
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

$principalRetirementSql
''';
}

/// Emits the step that runs before a principal's identity is removed.
///
/// Identity removal hard-deletes every row the principal owns through the
/// owner foreign keys, and a hard delete is never captured as a change. This
/// step therefore first hands each collaborative aggregate with an active
/// collaborator to its longest-standing collaborator, preferring one who may
/// edit, then tells every other audience what it is about to lose, so no
/// client keeps a stale copy.
String _emitPrincipalRetirementSql(EntityGraphSpec graph) {
  final functionName = 'retire_${snakeCase(graph.className)}_graph_principal';
  final owned = graph.entities
      .where((entity) => entity.ownership == Ownership.separate)
      .toList(growable: false);
  final ownedClasses = {for (final entity in owned) entity.className};
  final byClass = {
    for (final entity in graph.entities) entity.className: entity,
  };

  final succession = graph.entities
      .where((entity) => entity.security.collaboration != null)
      .where((entity) => ownedClasses.contains(entity.className))
      .map((target) => _successionSql(graph, target))
      .join('\n');

  final repairs = <String>[];
  for (final entity in owned) {
    for (final field in entity.ownershipReferenceFields) {
      final target = byClass[field.reference!.targetClassName]!;
      final guards = entity.participantFields
          .map(
            (participant) =>
                '\n        and dependent.${participant.columnName} is distinct '
                'from target.${field.reference!.ownershipSourceColumnName}',
          )
          .join();
      repairs.add(
        _repairSql(
          entity,
          comment:
              '${entity.className} follows its owner reference '
              '${field.name}.',
          update:
              'update public.${entity.tableName} dependent\n'
              '      set ${entity.ownerField.columnName} = '
              'target.${field.reference!.ownershipSourceColumnName},\n'
              '        ${entity.serverVersionField.columnName} = '
              'dependent.${entity.serverVersionField.columnName} + 1\n'
              '      from public.${target.tableName} target\n'
              '      where target.${target.idField.columnName} = '
              'dependent.${field.columnName}\n'
              '        and dependent.${entity.ownerField.columnName} = '
              'p_principal\n'
              '        and target.${field.reference!.ownershipSourceColumnName} '
              '<> p_principal$guards\n'
              '      returning dependent.${entity.idField.columnName} as id',
        ),
      );
    }
  }
  for (final aggregate in graph.entities) {
    for (final field in aggregate.fields.where(
      (field) => field.isComposition,
    )) {
      final component = byClass[field.reference!.targetClassName]!;
      if (!ownedClasses.contains(component.className) ||
          !ownedClasses.contains(aggregate.className)) {
        continue;
      }
      repairs.add(
        _repairSql(
          component,
          comment:
              '${component.className} follows its aggregate '
              '${aggregate.className}.${field.name}.',
          update:
              'update public.${component.tableName} dependent\n'
              '      set ${component.ownerField.columnName} = '
              'aggregate.${aggregate.ownerField.columnName},\n'
              '        ${component.serverVersionField.columnName} = '
              'dependent.${component.serverVersionField.columnName} + 1\n'
              '      from public.${aggregate.tableName} aggregate\n'
              '      where aggregate.${field.columnName} = '
              'dependent.${component.idField.columnName}\n'
              '        and dependent.${component.ownerField.columnName} = '
              'p_principal\n'
              '        and aggregate.${aggregate.ownerField.columnName} '
              '<> p_principal\n'
              '      returning dependent.${component.idField.columnName} as id',
        ),
      );
    }
  }
  for (final link in owned.where((entity) => entity.hasOwnershipReference)) {
    for (final field in link.accessTargetFields) {
      if (field.isOwnerReference ||
          field.isComposition ||
          field.accessTargetThroughColumnName != null) {
        continue;
      }
      final target = byClass[field.reference!.targetClassName]!;
      if (!ownedClasses.contains(target.className)) continue;
      // A target unique per owner, such as a tag name, could collide with the
      // link owner's own row and fail the whole retirement, so it leaves with
      // the principal and its links are retired instead.
      if (_hasOwnerScopedUniqueIndex(target)) continue;
      final active = [
        'link.${field.columnName} = dependent.${target.idField.columnName}',
        'link.${link.ownerField.columnName} <> p_principal',
        ..._relationshipActivePredicates(link, field, rowAlias: 'link'),
      ].join('\n            and ');
      repairs.add(
        _repairSql(
          target,
          comment:
              '${target.className} shared through ${link.className} '
              'follows the owner of that link.',
          update:
              'update public.${target.tableName} dependent\n'
              '      set ${target.ownerField.columnName} = (\n'
              '          select link.${link.ownerField.columnName} '
              'from public.${link.tableName} link\n'
              '          where $active\n'
              '          order by link.${link.idField.columnName}\n'
              '          limit 1\n'
              '        ),\n'
              '        ${target.serverVersionField.columnName} = '
              'dependent.${target.serverVersionField.columnName} + 1\n'
              '      where dependent.${target.ownerField.columnName} = '
              'p_principal\n'
              '        and exists (\n'
              '          select 1 from public.${link.tableName} link\n'
              '          where $active\n'
              '        )\n'
              '      returning dependent.${target.idField.columnName} as id',
        ),
      );
    }
  }

  final retirements = <String>[
    for (final target in graph.entities)
      if (target.security.collaboration case final collaboration?
          when collaboration.isDirect)
        '  -- Retire the principal\'s direct ${target.className} memberships.\n'
            '  delete from public.${collaboration.membershipTable}\n'
            '  where ${collaboration.userForeignKey} = p_principal;',
  ];
  for (final entity in owned) {
    final edge = _edgeRetirementSql(graph, entity, byClass);
    if (edge != null) retirements.add(edge);
  }
  final detachments = <String>[];
  final restrictedDeletes = <String>[];
  for (final entity in owned) {
    for (final field in entity.fields) {
      final reference = field.reference;
      if (reference == null ||
          field.isOwnerReference ||
          !ownedClasses.contains(reference.targetClassName)) {
        continue;
      }
      final target = byClass[reference.targetClassName]!;
      final referencesRetiredRow =
          'dependent.${entity.ownerField.columnName} <> p_principal\n'
          '    and dependent.${field.columnName} in (\n'
          '      select target.${target.idField.columnName} '
          'from public.${target.tableName} target\n'
          '      where target.${target.ownerField.columnName} = p_principal\n'
          '    )';
      final version =
          '${entity.serverVersionField.columnName} = '
          'dependent.${entity.serverVersionField.columnName} + 1';
      if (field.nullable &&
          (reference.hierarchy ||
              reference.onDelete == ReferenceDeleteAction.setNull)) {
        detachments.add(
          '  -- ${entity.className}.${field.name} detaches from a retired '
          '${target.className}.\n'
          '  update public.${entity.tableName} dependent\n'
          '  set ${field.columnName} = null, $version\n'
          '  where $referencesRetiredRow;',
        );
        continue;
      }
      final deletedAt = entity.deletedAtField;
      if (deletedAt != null) {
        detachments.add(
          '  -- ${entity.className}.${field.name} loses a retired '
          '${target.className}.\n'
          '  update public.${entity.tableName} dependent\n'
          '  set ${deletedAt.columnName} = now(), $version\n'
          '  where dependent.${deletedAt.columnName} is null\n'
          '    and $referencesRetiredRow;',
        );
      }
      if (reference.onDelete == ReferenceDeleteAction.restrict) {
        restrictedDeletes.add(
          '  delete from public.${entity.tableName} dependent\n'
          '  where $referencesRetiredRow;',
        );
      }
    }
  }

  final reannouncements = owned
      .map(
        (entity) =>
            '  update public.${entity.tableName} successor\n'
            '  set ${entity.serverVersionField.columnName} = '
            'successor.${entity.serverVersionField.columnName} + 1\n'
            '  where successor.${entity.idField.columnName} in (\n'
            '    select succession.entity_id '
            'from pg_temp.nodus_principal_successions succession\n'
            "    where succession.entity_type = ${_sqlLiteral(entity.className)}\n"
            '  );',
      )
      .join('\n');

  return '''-- Ownership succession and audience-safe retirement before a principal's
-- identity is removed. Callers delete the identity in the same transaction.

create or replace function public.$functionName(p_principal uuid)
returns void
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  handover record;
  moved_count bigint;
  repaired bigint;
begin
  if p_principal is null then
    raise exception 'Principal required' using errcode = '22004';
  end if;
  create temporary table if not exists nodus_principal_successions (
    entity_type text not null,
    entity_id uuid not null,
    primary key (entity_type, entity_id)
  ) on commit drop;
  truncate pg_temp.nodus_principal_successions;

$succession
  -- Rows derived from a successor-owned row follow it until nothing moves.
  loop
    repaired := 0;
${repairs.join('\n')}
    exit when repaired = 0;
  end loop;

${retirements.join('\n\n')}

${detachments.join('\n\n')}

  -- A successor last sees its inherited rows as their owner, after any
  -- revocation its own retired membership published.
$reannouncements

${restrictedDeletes.join('\n\n')}

  -- Every row still owned by the principal is removed with its identity, so
  -- its addressed copies become identity-only revocations. Addressed copies
  -- of inherited rows are superseded by their reannouncement. Everything
  -- else the principal could read is purged.
  with addressed as (
    delete from public.local_entity_changes changes
    where changes.owner_id = p_principal
      and changes.audience_user_id is not null
      and changes.audience_user_id <> p_principal
    returning changes.sequence, changes.entity_type, changes.entity_id,
      changes.owner_id, changes.server_version, changes.audience_user_id
  )
  insert into public.local_entity_changes (
    entity_type, entity_id, owner_id, server_version,
    operation_id, audience_user_id, is_revocation, record
  )
  select distinct on (addressed.entity_type, addressed.entity_id, addressed.audience_user_id)
    addressed.entity_type, addressed.entity_id, addressed.owner_id,
    addressed.server_version, null::uuid, addressed.audience_user_id, true,
    jsonb_build_object('id', addressed.entity_id)
  from addressed
  where not exists (
    select 1 from pg_temp.nodus_principal_successions succession
    where succession.entity_type = addressed.entity_type
      and succession.entity_id = addressed.entity_id
  )
  order by addressed.entity_type, addressed.entity_id,
    addressed.audience_user_id, addressed.sequence desc;
  delete from public.local_entity_changes changes
  where changes.audience_user_id = p_principal
    or (changes.audience_user_id is null and changes.owner_id = p_principal);
  delete from public.local_entity_operation_receipts receipts
  where receipts.user_id = p_principal;
end;
\$\$;

revoke all on function public.$functionName(uuid) from $supabaseApiRoles;''';
}

String _successionSql(EntityGraphSpec graph, EntitySpec target) {
  final collaboration = target.security.collaboration!;
  final String entityKey;
  final String userKey;
  final String activeMember;
  final String order;
  // A direct membership is a server-only row, so the successor's own row is
  // simply removed. A workflow membership is an entity and is retired with
  // the other rows that connect the principal to another user.
  final String retireSuccessorMembership;
  if (collaboration.isWorkflow) {
    final membership = graph.entities.singleWhere(
      (entity) => entity.tableName == collaboration.membershipTable,
    );
    final workflow = membership.workflowMembership!;
    entityKey = workflow.targetReference.columnName;
    userKey = workflow.participant.columnName;
    activeMember = [
      _workflowStatePredicate(
        'member.${workflow.status.columnName}',
        collaboration,
        includeReadableStates: false,
      ),
      if (membership.deletedAtField case final deletedAt?)
        'member.${deletedAt.columnName} is null',
    ].join('\n        and ');
    final createdAt = membership.fields
        .where((field) => field.name == EntityConventions.createdAtFieldName)
        .firstOrNull;
    // A member trusted to edit inherits before a read-only one.
    order = [
      if (collaboration.editPermissionField case final canEdit?)
        'member.$canEdit desc',
      if (createdAt != null) 'member.${createdAt.columnName}',
      'member.${membership.idField.columnName}',
    ].join(', ');
    retireSuccessorMembership = '';
  } else {
    entityKey = collaboration.entityForeignKey;
    userKey = collaboration.userForeignKey;
    activeMember = 'member.${collaboration.activeField}';
    order = 'member.$userKey';
    retireSuccessorMembership =
        '    delete from public.${collaboration.membershipTable}\n'
        '    where $entityKey = handover.entity_id\n'
        '      and $userKey = handover.successor_id;\n';
  }
  final liveRoot = target.deletedAtField == null
      ? ''
      : '\n      and root.${target.deletedAtField!.columnName} is null';
  final owner = target.ownerField.columnName;
  return '''  -- ${target.className} passes to its longest-standing active collaborator,
  -- preferring one who may edit.
  for handover in
    select root.${target.idField.columnName} as entity_id, (
      select member.$userKey from public.${collaboration.membershipTable} member
      where member.$entityKey = root.${target.idField.columnName}
        and $activeMember
        and member.$userKey <> p_principal
      order by $order
      limit 1
    ) as successor_id
    from public.${target.tableName} root
    where root.$owner = p_principal$liveRoot
  loop
    continue when handover.successor_id is null;
$retireSuccessorMembership    update public.${target.tableName}
    set $owner = handover.successor_id,
      ${target.serverVersionField.columnName} = ${target.serverVersionField.columnName} + 1
    where ${target.idField.columnName} = handover.entity_id;
    insert into pg_temp.nodus_principal_successions (entity_type, entity_id)
    values (${_sqlLiteral(target.className)}, handover.entity_id)
    on conflict do nothing;
  end loop;
''';
}

String _repairSql(
  EntitySpec entity, {
  required String comment,
  required String update,
}) =>
    '''    -- $comment
    with moved as (
      $update
    )
    insert into pg_temp.nodus_principal_successions (entity_type, entity_id)
    select ${_sqlLiteral(entity.className)}, moved.id from moved
    on conflict do nothing;
    get diagnostics moved_count = row_count;
    repaired := repaired + moved_count;''';

/// Retires live participant and relationship rows that connect the principal
/// to another user. Each row is revoked for its audience other than its owner
/// first, because that audience can no longer read the tombstone once the
/// identity cascade removes the row; the owner reads the tombstone itself.
String? _edgeRetirementSql(
  EntityGraphSpec graph,
  EntitySpec entity,
  Map<String, EntitySpec> byClass,
) {
  final directTargets = [
    for (final field in entity.accessTargetFields)
      if (!field.isComposition &&
          field.accessTargetThroughColumnName == null &&
          byClass[field.reference!.targetClassName]!.ownership ==
              Ownership.separate)
        (field, byClass[field.reference!.targetClassName]!),
  ];
  if (entity.participantFields.isEmpty && directTargets.isEmpty) return null;

  final owner = 'edge.${entity.ownerField.columnName}';
  final connections = [
    '$owner = p_principal',
    for (final participant in entity.participantFields)
      'edge.${participant.columnName} = p_principal',
    for (final (field, target) in directTargets)
      'exists (select 1 from public.${target.tableName} target '
          'where target.${target.idField.columnName} = '
          'edge.${field.columnName} and '
          'target.${target.ownerField.columnName} = p_principal)',
  ];
  final live = entity.deletedAtField == null
      ? ''
      : 'edge.${entity.deletedAtField!.columnName} is null\n    and ';
  final retired = '$live(\n      ${connections.join('\n      or ')}\n    )';

  final audience = entity.accessTargetFields.isEmpty
      ? entity.participantFields
            .map(
              (participant) =>
                  'select edge.${participant.columnName} as user_id',
            )
            .join(' union ')
      : _relationshipAudienceSelect(graph, entity, rowAlias: 'edge');
  final revocation =
      '''  with revoked as (
    select edge.${entity.idField.columnName} as entity_id,
      edge.${entity.ownerField.columnName} as owner_id,
      edge.${entity.serverVersionField.columnName} as server_version,
      audience.user_id
    from public.${entity.tableName} edge
    cross join lateral ($audience) audience
    where $retired
      and audience.user_id is not null
      and audience.user_id <> p_principal
      and audience.user_id <> $owner
  ), replaced as (
    delete from public.local_entity_changes changes
    using revoked
    where changes.entity_type = ${_sqlLiteral(entity.className)}
      and changes.entity_id = revoked.entity_id
      and changes.audience_user_id = revoked.user_id
  )
  insert into public.local_entity_changes (
    entity_type, entity_id, owner_id, server_version,
    operation_id, audience_user_id, is_revocation, record
  )
  select distinct ${_sqlLiteral(entity.className)}, revoked.entity_id,
    revoked.owner_id, revoked.server_version, null::uuid, revoked.user_id, true,
    jsonb_build_object('id', revoked.entity_id)
  from revoked;
''';
  final tombstone = entity.deletedAtField == null
      ? ''
      : '''  update public.${entity.tableName} edge
  set ${entity.deletedAtField!.columnName} = now(),
    ${entity.serverVersionField.columnName} = edge.${entity.serverVersionField.columnName} + 1
  where $retired;''';
  return '  -- Retire ${entity.className} rows connecting the principal to '
      'another user.\n$revocation$tombstone';
}

/// The `case` branch listing who may pull a change to [entity]: its owner and
/// every enumerable account that may read it now.
String _changeRecipientsCase(EntityGraphSpec graph, EntitySpec entity) {
  final when = "    when '${entity.className}' then";
  if (entity.isActivityEntry) {
    final source = graph.activityTrackings
        .singleWhere((tracking) => tracking.entry.className == entity.className)
        .source;
    final subject =
        '(select activity.subject_id from public.${entity.tableName} activity '
        'where activity.${entity.idField.columnName} = p_entity_id)';
    return _recipientsQuery(
      graph,
      source,
      when: when,
      entityId: subject,
      aliasPrefix: _sqlAlias('recipient_${entity.tableName}'),
    );
  }
  final selectPrincipals = entity.security.grants
      .where((grant) => grant.operation == RlsOperation.select)
      .map((grant) => grant.principal)
      .toSet();
  // Authenticated reads reaching here are not synchronized, so only the owner
  // and enumerable audiences pull the entity.
  if (selectPrincipals.difference({
        RlsPrincipal.owner,
        RlsPrincipal.authenticated,
      }).isEmpty &&
      !entity.relationshipAccessOperations.contains(RlsOperation.select)) {
    return '$when\n      return query select p_owner_id;';
  }
  return _recipientsQuery(
    graph,
    entity,
    when: when,
    entityId: 'p_entity_id',
    aliasPrefix: _sqlAlias('recipient_${entity.tableName}'),
  );
}

String _recipientsQuery(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String when,
  required String entityId,
  required String aliasPrefix,
}) {
  final candidates = [
    'select p_owner_id as user_id',
    ..._entityAudienceCandidates(
      graph,
      entity,
      entityId: entityId,
      aliasPrefix: aliasPrefix,
      includeReadableStates: true,
      followReferences: true,
    ),
  ];
  final readable = _readableByUserExpression(
    graph,
    entity,
    rowAlias: 'target_row',
    userExpression: 'candidate.user_id',
    includeReadableStates: true,
  );
  return '''$when
      return query
      select distinct candidate.user_id
      from (${candidates.join('\n        union ')}) candidate
      where candidate.user_id = p_owner_id
        or exists (
          select 1 from public.${entity.tableName} target_row
          where target_row.${entity.idField.columnName} = $entityId
            and ($readable)
        );''';
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
        aliasPrefix: 'access',
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

${_componentPublicationSql(graph, target, rowAlias: 'target_row', userExpression: 'p_user_id', indent: '  ')}  delete from public.local_entity_changes
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
        includeReadableStates: true,
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
  bool write = false,
}) {
  final expressions = <String>{
    for (final participant in relationship.participantFields)
      '$rowAlias.${participant.columnName} = $userExpression',
  };
  if (relationship.accessTargetFields.any((field) => field.isComposition)) {
    // A component is part of its aggregate's record, so it is readable exactly
    // when the aggregate itself is, including readable workflow states.
    expressions.add(
      _readableByUserExpression(
        graph,
        relationship,
        rowAlias: rowAlias,
        userExpression: userExpression,
        includeReadableStates: !write,
        write: write,
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
        write: write,
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
  bool includeReadableStates = false,
  bool followReferences = false,
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
        'and ${_workflowStatePredicate('$memberAlias.${workflow.status.columnName}', collaboration, includeReadableStates: includeReadableStates)} '
        'and $memberAlias.${membership.deletedAtField!.columnName} is null',
      );
    }
  }
  if (!followReferences &&
      (principals.contains(RlsPrincipal.authenticated) ||
          principals.contains(RlsPrincipal.reference))) {
    throw StateError(
      '${target.className} does not have a finite directly enumerable '
      'relationship-access audience.',
    );
  }
  // Reference access is the referenced targets' audience. Authenticated
  // reads are left out: those not synchronized are never pulled at all.
  if (followReferences && principals.contains(RlsPrincipal.reference)) {
    for (final (index, field) in target.accessReferenceFields.indexed) {
      final referenced = graph.entities.singleWhere(
        (entity) => entity.className == field.reference!.targetClassName,
      );
      final referenceAlias = _sqlAlias('${aliasPrefix}_reference_${index + 1}');
      candidates.addAll(
        _entityAudienceCandidates(
          graph,
          referenced,
          entityId:
              '(select $referenceAlias.${field.columnName} from '
              'public.${target.tableName} $referenceAlias where '
              '$referenceAlias.${target.idField.columnName} = $entityId)',
          aliasPrefix: referenceAlias,
          followReferences: true,
        ),
      );
    }
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
            followReferences: followReferences,
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
            followReferences: followReferences,
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

/// Users reaching [target] through relationships. Update and delete paths,
/// or any path serving a [write], require edit rights on every collaborative
/// source along the way.
String _relationshipAccessByUserExpression(
  EntityGraphSpec graph,
  EntitySpec target, {
  required RlsOperation operation,
  required String entityId,
  required String userExpression,
  required String aliasPrefix,
  bool write = false,
}) {
  final writes = write || operation != RlsOperation.select;
  final paths = <String>[];
  var index = 0;
  for (final relationship in graph.entities) {
    for (final field in relationship.accessTargetFields) {
      for (final destination in _accessTargetDestinations(graph, field)) {
        if (destination.target.className != target.className ||
            !destination.operations.contains(operation)) {
          continue;
        }
        final alias = _sqlAlias('${aliasPrefix}_path_${index++}');
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
          write: writes,
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
    final editorSql = switch (collaboration.editPermissionField) {
      null => '',
      final column =>
        '''

create or replace function public.is_${target.tableName}_editor(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as \$\$
  select exists (
    select 1 from public.${membership.tableName} member
    where member.${workflow.targetReference.columnName} = p_id
      and member.${workflow.participant.columnName} = auth.uid()
      and member.${workflow.status.columnName} = $accepted
      and member.$column
      and member.${deletedAt.columnName} is null
  );
\$\$;

revoke all on function public.is_${target.tableName}_editor(uuid) from $supabaseApiRoles;
grant execute on function public.is_${target.tableName}_editor(uuid) to authenticated;''',
    };
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
grant execute on function public.is_${target.tableName}_viewer(uuid) to authenticated;$editorSql

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

${_componentPublicationSql(graph, target, rowAlias: 'target_row', userExpression: 'new.${workflow.participant.columnName}', indent: '    ')}    delete from public.local_entity_changes
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
grant execute on function public.is_${target.tableName}_collaborator(uuid) to authenticated;$editorSql

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

${_componentPublicationSql(graph, target, rowAlias: 'target_row', userExpression: 'new.${workflow.participant.columnName}', indent: '  ')}  delete from public.local_entity_changes
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
      for (final (field, component) in _publishedCompositions(
        graph,
        dependent,
      )) {
        body
          ..writeln(
            '  perform public.publish_${component.tableName}_relationship_access(',
          )
          ..writeln('    entity.${field.columnName}, p_user_id')
          ..writeln('  )')
          ..writeln('  from public.${dependent.tableName} entity')
          ..writeln('  where $affected;');
      }
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

/// Composition fields of [aggregate] whose component has derived read access.
Iterable<(FieldSpec, EntitySpec)> _publishedCompositions(
  EntityGraphSpec graph,
  EntitySpec aggregate,
) sync* {
  for (final field in aggregate.fields.where((field) => field.isComposition)) {
    final component = graph.entities.singleWhere(
      (entity) => entity.className == field.reference!.targetClassName,
    );
    if (component.relationshipAccessOperations.contains(RlsOperation.select)) {
      yield (field, component);
    }
  }
}

/// Publishes [aggregate]'s components to a user whose access to the aggregate
/// changed. It runs before the aggregate row is published, so an inbound
/// aggregate never reaches a client without the component its record needs.
String _componentPublicationSql(
  EntityGraphSpec graph,
  EntitySpec aggregate, {
  required String rowAlias,
  required String userExpression,
  required String indent,
}) => _publishedCompositions(graph, aggregate)
    .map(
      (composition) =>
          '${indent}perform public.publish_${composition.$2.tableName}_relationship_access(\n'
          '$indent  $rowAlias.${composition.$1.columnName},\n'
          '$indent  $userExpression\n'
          '$indent);\n',
    )
    .join();

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

/// Users reaching [entity] through its select grants. A [write] narrows
/// collaborators to editors so the reach can authorize derived writes.
String _readableByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String rowAlias,
  required String userExpression,
  bool includeReadableStates = false,
  bool write = false,
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
          includeReadableStates: includeReadableStates,
          write: write,
        ),
      )
      .toSet();
  // Seeing an entity through a relationship never grants writing through it;
  // a write follows the relationship's update access.
  final relationshipOperation = write
      ? RlsOperation.update
      : RlsOperation.select;
  if (entity.relationshipAccessOperations.contains(relationshipOperation)) {
    expressions.add(
      _relationshipAccessByUserExpression(
        graph,
        entity,
        operation: relationshipOperation,
        entityId: '$rowAlias.${entity.idField.columnName}',
        userExpression: userExpression,
        aliasPrefix: _sqlAlias(
          '${rowAlias}_${entity.tableName}_relationship_'
          '${relationshipOperation.name}',
        ),
        write: write,
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
  bool includeReadableStates = false,
  bool write = false,
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
    includeReadableStates: includeReadableStates,
    write: write,
  ),
  RlsPrincipal.reference => _referencesByUserExpression(
    graph,
    entity,
    rowAlias: rowAlias,
    userExpression: userExpression,
    write: write,
  ),
  RlsPrincipal.relationship => _relationshipAccessByUserExpression(
    graph,
    entity,
    operation: RlsOperation.select,
    entityId: '$rowAlias.${entity.idField.columnName}',
    userExpression: userExpression,
    aliasPrefix: _sqlAlias(
      '${rowAlias}_${entity.tableName}_relationship_select',
    ),
    write: write,
  ),
  RlsPrincipal.authenticated => '$userExpression is not null',
};

String _collaboratorByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String entityId,
  required String userExpression,
  bool includeReadableStates = false,
  bool write = false,
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
      'and ${_workflowStatePredicate('member.${workflow.status.columnName}', collaboration, includeReadableStates: includeReadableStates && !write)} '
      '${write && collaboration.separatesEditors ? 'and member.${collaboration.editPermissionField} ' : ''}'
      'and member.${deletedAt.columnName} is null)';
}

/// Matches active workflow members, or every readable state when the caller
/// derives visibility that must equal the collaboration target's own select.
String _workflowStatePredicate(
  String column,
  CollaborationSpec collaboration, {
  required bool includeReadableStates,
}) => includeReadableStates && collaboration.hasAdditionalReadableStates
    ? '$column in (${collaboration.readableValues.map(_sqlLiteral).join(', ')})'
    : '$column = ${_sqlLiteral(collaboration.acceptedValue!)}';

String _referencesByUserExpression(
  EntityGraphSpec graph,
  EntitySpec entity, {
  required String rowAlias,
  required String userExpression,
  bool write = false,
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
                write: write,
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

bool _hasOwnerScopedUniqueIndex(EntitySpec entity) =>
    entity.postgresIndexes.any(
      (index) =>
          index.unique && index.fieldNames.contains(entity.ownerField.name),
    );
