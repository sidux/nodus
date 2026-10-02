-- Sync conflicts raise PostgREST status code PT409 instead of the 40001
-- serialization failure PostgREST retries without bound, and a deleted row no
-- longer holds an unconditional unique key.
--
-- Regenerated from the Nodus declarations.

drop index if exists "public"."task_activities_source_operation_id_idx";

CREATE UNIQUE INDEX task_activities_source_operation_id_active_idx ON public.task_activities USING btree (source_operation_id) WHERE (deleted_at IS NULL);

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.apply_task_projects_patch(p_id uuid, p_base_server_version bigint, p_operation text, p_patch jsonb)
 RETURNS public.task_projects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_row public.task_projects;
  updated_row public.task_projects;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_operation not in ('patch', 'delete') then
    raise exception 'Unsupported operation' using errcode = '22023';
  end if;
  if p_operation = 'patch' and not (public.is_task_projects_owner(p_id)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  if p_operation = 'delete' and not (public.is_task_projects_owner(p_id)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  if p_operation = 'patch' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any(array['title']::text[]))
  ) then
    raise exception 'Patch contains a forbidden field' using errcode = '22023';
  end if;
  if p_operation = 'delete' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any(array['deletedAt']::text[]))
  ) then
    raise exception 'Delete contains a forbidden field' using errcode = '22023';
  end if;
  if p_operation = 'delete' and (select count(*) from jsonb_object_keys(p_patch)) <> 1 then
    raise exception 'Delete requires exactly one command field' using errcode = '22023';
  end if;

  select * into current_row from public.task_projects where id = p_id for update;
  if not found then
    raise exception 'Entity not found' using errcode = 'P0002';
  end if;
  if current_row.server_version <> p_base_server_version then
    raise exception 'Version conflict' using errcode = 'PT409';
  end if;
  update public.task_projects
  set
    title = case when p_operation = 'patch' and p_patch ? 'title' then p_patch -> 'title' #>> '{}' else current_row.title end,
    deleted_at = case when p_operation = 'delete' and p_patch ? 'deletedAt' then (p_patch -> 'deletedAt' #>> '{}')::timestamptz else current_row.deleted_at end
    , server_version = current_row.server_version + 1
  where id = p_id
  returning * into updated_row;
  return updated_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.apply_tasks_patch(p_id uuid, p_base_server_version bigint, p_operation text, p_patch jsonb)
 RETURNS public.tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_row public.tasks;
  updated_row public.tasks;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_operation not in ('patch', 'delete') then
    raise exception 'Unsupported operation' using errcode = '22023';
  end if;
  if p_operation = 'patch' and not (public.is_tasks_owner(p_id) or public.is_tasks_collaborator(p_id)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  if p_operation = 'delete' and not (public.is_tasks_owner(p_id)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  if p_operation = 'patch' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any(array['title', 'description', 'status', 'priority', 'dueAt', 'completedAt', 'archivedAt']::text[]))
  ) then
    raise exception 'Patch contains a forbidden field' using errcode = '22023';
  end if;
  if p_operation = 'delete' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any(array['deletedAt']::text[]))
  ) then
    raise exception 'Delete contains a forbidden field' using errcode = '22023';
  end if;
  if p_operation = 'delete' and (select count(*) from jsonb_object_keys(p_patch)) <> 1 then
    raise exception 'Delete requires exactly one command field' using errcode = '22023';
  end if;
  if (p_patch) ? 'projectId' and jsonb_typeof(p_patch -> 'projectId') <> 'null' and not (public.is_task_projects_owner((p_patch ->> 'projectId')::uuid)) then
    raise exception 'Referenced entity access denied' using errcode = '42501';
  end if;
  select * into current_row from public.tasks where id = p_id for update;
  if not found then
    raise exception 'Entity not found' using errcode = 'P0002';
  end if;
  if p_operation = 'patch' and p_patch ? 'archivedAt'
     and not ((p_patch ?& array['archivedAt']::text[] and p_patch -> 'archivedAt' <> 'null'::jsonb and (current_row.archived_at is null or current_row.archived_at is not distinct from ((p_patch -> 'archivedAt' #>> '{}')::timestamptz))) or (p_patch ?& array['archivedAt']::text[] and p_patch -> 'archivedAt' = 'null'::jsonb)) then
    raise exception 'Patch does not match a declared entity action' using errcode = '22023';
  end if;
  if p_operation = 'patch' and p_patch ? 'completedAt'
     and not ((p_patch ?& array['status', 'completedAt']::text[] and (p_patch -> 'status' #>> '{}') is not distinct from 'in_progress' and p_patch -> 'completedAt' = 'null'::jsonb) or (p_patch ?& array['status', 'completedAt']::text[] and (p_patch -> 'status' #>> '{}') is not distinct from 'done' and p_patch -> 'completedAt' <> 'null'::jsonb and (current_row.completed_at is null or current_row.completed_at is not distinct from ((p_patch -> 'completedAt' #>> '{}')::timestamptz))) or (p_patch ?& array['status', 'completedAt']::text[] and (p_patch -> 'status' #>> '{}') is not distinct from 'todo' and p_patch -> 'completedAt' = 'null'::jsonb)) then
    raise exception 'Patch does not match a declared entity action' using errcode = '22023';
  end if;
  if p_operation = 'patch' and p_patch ? 'status'
     and not ((p_patch ?& array['status', 'completedAt']::text[] and (p_patch -> 'status' #>> '{}') is not distinct from 'in_progress' and p_patch -> 'completedAt' = 'null'::jsonb) or (p_patch ?& array['status', 'completedAt']::text[] and (p_patch -> 'status' #>> '{}') is not distinct from 'done' and p_patch -> 'completedAt' <> 'null'::jsonb and (current_row.completed_at is null or current_row.completed_at is not distinct from ((p_patch -> 'completedAt' #>> '{}')::timestamptz))) or (p_patch ?& array['status', 'completedAt']::text[] and (p_patch -> 'status' #>> '{}') is not distinct from 'todo' and p_patch -> 'completedAt' = 'null'::jsonb)) then
    raise exception 'Patch does not match a declared entity action' using errcode = '22023';
  end if;
  if p_operation = 'patch' and p_patch ? 'status'
     and current_row.status is distinct from (p_patch -> 'status' #>> '{}')
     and not ((current_row.status = 'todo' and (p_patch -> 'status' #>> '{}') = 'in_progress' and (public.is_tasks_owner(p_id) or public.is_tasks_collaborator(p_id))) or (current_row.status = 'todo' and (p_patch -> 'status' #>> '{}') = 'done' and (public.is_tasks_owner(p_id) or public.is_tasks_collaborator(p_id))) or (current_row.status = 'in_progress' and (p_patch -> 'status' #>> '{}') = 'todo' and (public.is_tasks_owner(p_id) or public.is_tasks_collaborator(p_id))) or (current_row.status = 'in_progress' and (p_patch -> 'status' #>> '{}') = 'done' and (public.is_tasks_owner(p_id) or public.is_tasks_collaborator(p_id))) or (current_row.status = 'done' and (p_patch -> 'status' #>> '{}') = 'todo' and (public.is_tasks_owner(p_id) or public.is_tasks_collaborator(p_id)))) then
    raise exception 'State transition is not allowed' using errcode = '23514';
  end if;
  if current_row.server_version <> p_base_server_version then
    raise exception 'Version conflict' using errcode = 'PT409';
  end if;
  update public.tasks
  set
    title = case when p_operation = 'patch' and p_patch ? 'title' then p_patch -> 'title' #>> '{}' else current_row.title end,
    description = case when p_operation = 'patch' and p_patch ? 'description' then p_patch -> 'description' #>> '{}' else current_row.description end,
    status = case when p_operation = 'patch' and p_patch ? 'status' then p_patch -> 'status' #>> '{}' else current_row.status end,
    priority = case when p_operation = 'patch' and p_patch ? 'priority' then p_patch -> 'priority' #>> '{}' else current_row.priority end,
    due_at = case when p_operation = 'patch' and p_patch ? 'dueAt' then (p_patch -> 'dueAt' #>> '{}')::timestamptz else current_row.due_at end,
    completed_at = case when p_operation = 'patch' and p_patch ? 'completedAt' then (p_patch -> 'completedAt' #>> '{}')::timestamptz else current_row.completed_at end,
    archived_at = case when p_operation = 'patch' and p_patch ? 'archivedAt' then (p_patch -> 'archivedAt' #>> '{}')::timestamptz else current_row.archived_at end,
    deleted_at = case when p_operation = 'delete' and p_patch ? 'deletedAt' then (p_patch -> 'deletedAt' #>> '{}')::timestamptz else current_row.deleted_at end
    , server_version = current_row.server_version + 1
  where id = p_id
  returning * into updated_row;
  return updated_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.push_task_projects_operations(p_operations jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_operation jsonb;
  operation_uuid uuid;
  receipt_result jsonb;
  canonical public.task_projects;
  lower_order_rank numeric;
  upper_order_rank numeric;
  anchor_order_rank numeric;
  next_order_rank numeric;
  current_order_scope_version bigint;
  order_scope_key text;
  order_scope_membership_changed boolean;
  order_scope_versions jsonb := '[]'::jsonb;
  related_changes jsonb;
  change_sequence bigint;
  results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_operations) <> 'array' then
    raise exception 'Operations must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'At most 100 operations are allowed per batch' using errcode = '22023';
  end if;
  for current_operation in select value from jsonb_array_elements(p_operations) loop
    current_order_scope_version := null;
    order_scope_membership_changed := false;
    order_scope_versions := '[]'::jsonb;
    current_operation := public.upcast_task_projects_operation(current_operation);
    operation_uuid := (current_operation ->> 'operationId')::uuid;
    if current_operation ->> 'entityType' <> 'TaskProject' then
      raise exception 'Unexpected entity type' using errcode = '22023';
    end if;
    if coalesce((current_operation ->> 'protocolVersion')::integer, 0) <> 2 then
      raise exception 'Unsupported protocol version' using errcode = '22023';
    end if;
    if jsonb_typeof(current_operation -> 'patch') <> 'object' then
      raise exception 'Patch must be an object' using errcode = '22023';
    end if;
    select receipt.result into receipt_result from public.local_entity_operation_receipts receipt where receipt.operation_id = operation_uuid and receipt.user_id = auth.uid();
    if found then
      results := results || jsonb_build_array(receipt_result);
      continue;
    end if;
    perform set_config('app.operation_id', operation_uuid::text, true);
    if current_operation ->> 'operation' not in ('create', 'patch', 'delete', 'command') then
      raise exception 'Unsupported operation' using errcode = '22023';
    end if;
    if current_operation ->> 'operation' = 'create' then
      if exists (select 1 from jsonb_object_keys(current_operation -> 'patch') key
          where not (key = any(array['id', 'ownerId', 'title', 'orderRank']::text[])))
          or not ((current_operation -> 'patch') ?& array['id', 'ownerId', 'title'])
          or (not (current_operation ? 'orderedCreate') and not ((current_operation -> 'patch') ? 'orderRank')) then
        raise exception 'Create contains missing or forbidden fields' using errcode = '22023';
      end if;
      if (current_operation -> 'patch' ->> 'id')::uuid
          <> (current_operation ->> 'entityId')::uuid then
        raise exception 'Create entity ID mismatch' using errcode = '22023';
      end if;
      if not ((current_operation -> 'patch' ->> 'ownerId')::uuid = auth.uid()) then
        raise exception 'Create access denied' using errcode = '42501';
      end if;
      if (current_operation -> 'patch' ->> 'ownerId')::uuid
          <> auth.uid() then
        raise exception 'Owner must match authenticated user' using errcode = '42501';
      end if;

      order_scope_key := current_operation -> 'patch' ->> 'ownerId';
      perform pg_advisory_xact_lock(
        hashtextextended('TaskProject:' || order_scope_key, 0)
      );
      insert into public.local_entity_order_scopes (entity_type, scope_key)
      values ('TaskProject', order_scope_key)
      on conflict (entity_type, scope_key) do nothing;
      if current_operation ? 'orderedCreate' then
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
        where scope.entity_type = 'TaskProject'
          and scope.scope_key = order_scope_key
        for update;
        if (current_operation -> 'orderedCreate' ->>
              'scopeBaseVersion')::bigint > current_order_scope_version then
          raise exception 'Ordered scope base version is ahead of the server'
            using errcode = '22023';
        end if;
        if current_operation -> 'orderedCreate' ->> 'placement' = 'first' then
          lower_order_rank := 0;
          select member.order_rank::numeric into upper_order_rank
          from public.task_projects member
          where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid)
          order by member.order_rank, member.id
          limit 1;
          if not found then
            upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
          end if;
        else
          upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
          select member.order_rank::numeric into lower_order_rank
          from public.task_projects member
          where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid)
          order by member.order_rank desc,
                   member.id desc
          limit 1;
          if not found then
            lower_order_rank := 0;
          end if;
        end if;
        next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
        if next_order_rank <= lower_order_rank
           or next_order_rank >= upper_order_rank then
          with ordered_scope as (
            select
              member.id as member_id,
              row_number() over (
                order by member.order_rank,
                         member.id
              ) as position,
              count(*) over () as scope_size
            from public.task_projects member
            where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid)
          ), rebalanced as (
            select
              member_id,
              trunc(
                (115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric * position::numeric) /
                (scope_size::numeric + 1)
              ) as next_rank
            from ordered_scope
          )
          update public.task_projects member
          set order_rank = lpad(rebalanced.next_rank::text, 78, '0'),
              server_version =
                member.server_version + 1
          from rebalanced
          where member.id = rebalanced.member_id;
          if current_operation -> 'orderedCreate' ->> 'placement' = 'first' then
            lower_order_rank := 0;
            select member.order_rank::numeric into upper_order_rank
            from public.task_projects member
            where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid)
            order by member.order_rank, member.id
            limit 1;
          else
            upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
            select member.order_rank::numeric into lower_order_rank
            from public.task_projects member
            where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid)
            order by member.order_rank desc,
                     member.id desc
            limit 1;
          end if;
          next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
          if next_order_rank <= lower_order_rank
             or next_order_rank >= upper_order_rank then
            raise exception 'Ordered scope rank rebalance failed'
              using errcode = 'P0001';
          end if;
        end if;
        current_operation := jsonb_set(
          current_operation,
          '{patch,orderRank}',
          to_jsonb(lpad(next_order_rank::text, 78, '0')),
          true
        );
      end if;
      insert into public.task_projects (id, owner_id, title, order_rank)
      values ((current_operation -> 'patch' -> 'id' #>> '{}')::uuid, (current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid, current_operation -> 'patch' -> 'title' #>> '{}', current_operation -> 'patch' -> 'orderRank' #>> '{}') returning * into canonical;
      update public.local_entity_order_scopes
      set version = version + 1
      where entity_type = 'TaskProject' and scope_key = order_scope_key
      returning version into current_order_scope_version;
    elsif current_operation ->> 'operation' = 'command' then
      if current_operation ->> 'commandName' = 'moveInOrder' then
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
  if not (public.is_task_projects_owner((current_operation ->> 'entityId')::uuid)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  select owner_id::text into order_scope_key
  from public.task_projects
  where id = (current_operation ->> 'entityId')::uuid
    and deleted_at is null;
  if not found then
    raise exception 'Ordered entity not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('TaskProject:' || order_scope_key, 0)
  );
  select candidate.* into canonical from public.task_projects candidate
  where candidate.id = (current_operation ->> 'entityId')::uuid
    and candidate.deleted_at is null
    and candidate.owner_id::text = order_scope_key
  for update;
  if not found then
    raise exception 'Ordered entity left its canonical scope' using errcode = 'PT409';
  end if;
  insert into public.local_entity_order_scopes (entity_type, scope_key)
  values ('TaskProject', order_scope_key)
  on conflict (entity_type, scope_key) do nothing;
  select scope.version into current_order_scope_version
  from public.local_entity_order_scopes scope
  where scope.entity_type = 'TaskProject'
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
  if current_operation -> 'patch' ->> 'placement' = 'first' then
    lower_order_rank := 0;
    select neighbor.order_rank::numeric into upper_order_rank
    from public.task_projects neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
    order by neighbor.order_rank, neighbor.id
    limit 1;
    if not found then
      upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    end if;
  elsif current_operation -> 'patch' ->> 'placement' = 'last' then
    upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    select neighbor.order_rank::numeric into lower_order_rank
    from public.task_projects neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
    order by neighbor.order_rank desc,
             neighbor.id desc
    limit 1;
    if not found then
      lower_order_rank := 0;
    end if;
  else
    select neighbor.order_rank::numeric into anchor_order_rank
    from public.task_projects neighbor
    where neighbor.id =
        (current_operation -> 'patch' ->> 'anchorId')::uuid
      and neighbor.deleted_at is null and neighbor.owner_id is not distinct from canonical.owner_id;
    if not found then
      raise exception 'Ordered anchor is outside the canonical scope'
        using errcode = '22023';
    end if;
    if current_operation -> 'patch' ->> 'placement' = 'before' then
      upper_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into lower_order_rank
      from public.task_projects neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
        and (neighbor.order_rank,
             neighbor.id) <
            (lpad(anchor_order_rank::text, 78, '0'),
             (current_operation -> 'patch' ->> 'anchorId')::uuid)
      order by neighbor.order_rank desc,
               neighbor.id desc
      limit 1;
      if not found then
        lower_order_rank := 0;
      end if;
    else
      lower_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into upper_order_rank
      from public.task_projects neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
        and (neighbor.order_rank,
             neighbor.id) >
            (lpad(anchor_order_rank::text, 78, '0'),
             (current_operation -> 'patch' ->> 'anchorId')::uuid)
      order by neighbor.order_rank, neighbor.id
      limit 1;
      if not found then
        upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
      end if;
    end if;
  end if;
  next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
  if next_order_rank <= lower_order_rank or next_order_rank >= upper_order_rank then
  with ordered_scope as (
      select
        member.id as member_id,
        row_number() over (
          order by member.order_rank, member.id
        ) as position,
        count(*) over () as scope_size
      from public.task_projects member
      where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id
    ), rebalanced as (
      select
        member_id,
        trunc(
          (115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric * position::numeric) /
          (scope_size::numeric + 1)
        ) as next_rank
      from ordered_scope
    )
    update public.task_projects member
    set order_rank = lpad(rebalanced.next_rank::text, 78, '0'),
        server_version =
          member.server_version + 1
    from rebalanced
    where member.id = rebalanced.member_id;
    if current_operation -> 'patch' ->> 'placement' = 'first' then
    lower_order_rank := 0;
    select neighbor.order_rank::numeric into upper_order_rank
    from public.task_projects neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
    order by neighbor.order_rank, neighbor.id
    limit 1;
    if not found then
      upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    end if;
  elsif current_operation -> 'patch' ->> 'placement' = 'last' then
    upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    select neighbor.order_rank::numeric into lower_order_rank
    from public.task_projects neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
    order by neighbor.order_rank desc,
             neighbor.id desc
    limit 1;
    if not found then
      lower_order_rank := 0;
    end if;
  else
    select neighbor.order_rank::numeric into anchor_order_rank
    from public.task_projects neighbor
    where neighbor.id =
        (current_operation -> 'patch' ->> 'anchorId')::uuid
      and neighbor.deleted_at is null and neighbor.owner_id is not distinct from canonical.owner_id;
    if not found then
      raise exception 'Ordered anchor is outside the canonical scope'
        using errcode = '22023';
    end if;
    if current_operation -> 'patch' ->> 'placement' = 'before' then
      upper_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into lower_order_rank
      from public.task_projects neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
        and (neighbor.order_rank,
             neighbor.id) <
            (lpad(anchor_order_rank::text, 78, '0'),
             (current_operation -> 'patch' ->> 'anchorId')::uuid)
      order by neighbor.order_rank desc,
               neighbor.id desc
      limit 1;
      if not found then
        lower_order_rank := 0;
      end if;
    else
      lower_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into upper_order_rank
      from public.task_projects neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id
        and (neighbor.order_rank,
             neighbor.id) >
            (lpad(anchor_order_rank::text, 78, '0'),
             (current_operation -> 'patch' ->> 'anchorId')::uuid)
      order by neighbor.order_rank, neighbor.id
      limit 1;
      if not found then
        upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
      end if;
    end if;
  end if;
    next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
    if next_order_rank <= lower_order_rank
       or next_order_rank >= upper_order_rank then
      raise exception 'Ordered scope rank rebalance failed' using errcode = 'P0001';
    end if;
  end if;
  update public.task_projects
  set order_rank = lpad(next_order_rank::text, 78, '0'),
      server_version =
        server_version + 1
  where id = canonical.id
  returning * into canonical;
  update public.local_entity_order_scopes scope
  set version = scope.version + 1
  where scope.entity_type = 'TaskProject'
    and scope.scope_key = order_scope_key
  returning scope.version into current_order_scope_version;
      elsif current_operation ->> 'commandName' = 'reorder' then
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
  select owner_id::text into order_scope_key
  from public.task_projects
  where id = (current_operation ->> 'entityId')::uuid
    and deleted_at is null;
  if not found then
    raise exception 'Ordered entity not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('TaskProject:' || order_scope_key, 0)
  );
  select candidate.* into canonical from public.task_projects candidate
  where candidate.id = (current_operation ->> 'entityId')::uuid
    and candidate.deleted_at is null
    and candidate.owner_id::text = order_scope_key
  for update;
  if not found then
    raise exception 'Ordered entity left its canonical scope' using errcode = 'PT409';
  end if;
  insert into public.local_entity_order_scopes (entity_type, scope_key)
  values ('TaskProject', order_scope_key)
  on conflict (entity_type, scope_key) do nothing;
  select scope.version into current_order_scope_version
  from public.local_entity_order_scopes scope
  where scope.entity_type = 'TaskProject'
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
      select member.id as member_id
      from public.task_projects member
      where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id
    )
    select 1
    from requested
    full outer join active_members using (member_id)
    where requested.member_id is null or active_members.member_id is null
  ) then
    raise exception 'Exact ordered membership changed' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from (
      select value::uuid as member_id
      from jsonb_array_elements_text(
        current_operation -> 'patch' -> 'orderedIds'
      )
    ) requested
    where not (public.is_task_projects_owner(requested.member_id))
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
  update public.task_projects member
  set order_rank = lpad(
        trunc((115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric * requested.position) /
          (requested.scope_size + 1))::text,
        78,
        '0'
      ),
      server_version =
        member.server_version + 1
  from requested
  where member.id = requested.member_id;
  select * into canonical from public.task_projects
  where id = (current_operation ->> 'entityId')::uuid;
  update public.local_entity_order_scopes scope
  set version = scope.version + 1
  where scope.entity_type = 'TaskProject'
    and scope.scope_key = order_scope_key
  returning scope.version into current_order_scope_version;
      else
        raise exception 'Unsupported command' using errcode = '22023';
      end if;
    elsif current_operation ->> 'operation' in ('patch', 'delete') then
      if current_operation -> 'patch' ?| array['deletedAt'] then
        if current_operation ->> 'operation' = 'delete'
           and not (public.is_task_projects_owner((current_operation ->> 'entityId')::uuid)) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        if current_operation ->> 'operation' = 'patch'
           and not (public.is_task_projects_owner((current_operation ->> 'entityId')::uuid)) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        select candidate.owner_id::text,
               (candidate.deleted_at is null) <>
                 (case
      when current_operation -> 'patch' ? 'deletedAt' then
        current_operation -> 'patch' -> 'deletedAt' = 'null'::jsonb
      else candidate.deleted_at is null
    end)
        into order_scope_key, order_scope_membership_changed
        from public.task_projects candidate
        where candidate.id =
          (current_operation ->> 'entityId')::uuid;
        if not found then
          raise exception 'Entity not found' using errcode = 'P0002';
        end if;
        if order_scope_membership_changed then
          perform pg_advisory_xact_lock(
            hashtextextended('TaskProject:' || order_scope_key, 0)
          );
          insert into public.local_entity_order_scopes (entity_type, scope_key)
          values ('TaskProject', order_scope_key)
          on conflict (entity_type, scope_key) do nothing;
          select scope.version into current_order_scope_version
          from public.local_entity_order_scopes scope
          where scope.entity_type = 'TaskProject'
            and scope.scope_key = order_scope_key
          for update;
        end if;
      end if;
      canonical := public.apply_task_projects_patch(
        (current_operation ->> 'entityId')::uuid,
        (current_operation ->> 'baseServerVersion')::bigint,
        current_operation ->> 'operation',
        current_operation -> 'patch');
      if order_scope_membership_changed then
        update public.local_entity_order_scopes
        set version = version + 1
        where entity_type = 'TaskProject' and scope_key = order_scope_key
        returning version into current_order_scope_version;
      end if;
    end if;
    select changes.sequence into change_sequence from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.entity_type = 'TaskProject' and changes.entity_id = canonical.id order by changes.sequence desc limit 1;
    if change_sequence is null then
      raise exception 'Accepted operation has no change-log entry' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('entityType', changes.entity_type, 'record', changes.record, 'sequence', changes.sequence, 'operationId', changes.operation_id, 'serverVersion', changes.server_version) order by changes.sequence), '[]'::jsonb) into related_changes from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.audience_user_id is null and not changes.is_revocation and not (changes.entity_type = 'TaskProject' and changes.entity_id = canonical.id);
    if current_order_scope_version is not null then
      order_scope_versions := jsonb_build_array(
        jsonb_build_object('scope', jsonb_build_object('ownerId', canonical.owner_id), 'version', current_order_scope_version)
      );
    end if;
    receipt_result := jsonb_build_object('record', to_jsonb(canonical), 'sequence', change_sequence, 'operationId', operation_uuid, 'serverVersion', canonical.server_version, 'scopeVersions', order_scope_versions, 'relatedChanges', related_changes);
    insert into public.local_entity_operation_receipts (operation_id, user_id, entity_type, entity_id, result) values (operation_uuid, auth.uid(), 'TaskProject', canonical.id, receipt_result);
    results := results || jsonb_build_array(receipt_result);
  end loop;
  return results;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.push_tasks_operations(p_operations jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_operation jsonb;
  operation_uuid uuid;
  receipt_result jsonb;
  canonical public.tasks;
  lower_order_rank numeric;
  upper_order_rank numeric;
  anchor_order_rank numeric;
  next_order_rank numeric;
  current_order_scope_version bigint;
  order_scope_key text;
  order_scope_membership_changed boolean;
  rebalance_window_size integer;
  rebalance_member_ids uuid[];
  rebalance_member_count integer;
  rebalance_outside_rank numeric;
  rebalance_lower_rank numeric;
  rebalance_upper_rank numeric;
  rebalance_step numeric;
  rebalance_has_outside boolean;
  order_scope_versions jsonb := '[]'::jsonb;
  source_order_scope_key text;
  target_order_scope_key text;
  source_order_scope_version bigint;
  target_order_scope_version bigint;
  source_order_scope jsonb;
  target_order_scope jsonb;
  related_changes jsonb;
  change_sequence bigint;
  results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_operations) <> 'array' then
    raise exception 'Operations must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'At most 100 operations are allowed per batch' using errcode = '22023';
  end if;
  for current_operation in select value from jsonb_array_elements(p_operations) loop
    current_order_scope_version := null;
    order_scope_membership_changed := false;
    order_scope_versions := '[]'::jsonb;
    current_operation := public.upcast_tasks_operation(current_operation);
    operation_uuid := (current_operation ->> 'operationId')::uuid;
    if current_operation ->> 'entityType' <> 'Task' then
      raise exception 'Unexpected entity type' using errcode = '22023';
    end if;
    if coalesce((current_operation ->> 'protocolVersion')::integer, 0) <> 3 then
      raise exception 'Unsupported protocol version' using errcode = '22023';
    end if;
    if jsonb_typeof(current_operation -> 'patch') <> 'object' then
      raise exception 'Patch must be an object' using errcode = '22023';
    end if;
    select receipt.result into receipt_result from public.local_entity_operation_receipts receipt where receipt.operation_id = operation_uuid and receipt.user_id = auth.uid();
    if found then
      results := results || jsonb_build_array(receipt_result);
      continue;
    end if;
    perform set_config('app.operation_id', operation_uuid::text, true);
    if current_operation ->> 'operation' not in ('create', 'patch', 'delete', 'command') then
      raise exception 'Unsupported operation' using errcode = '22023';
    end if;
    if current_operation ->> 'operation' = 'create' then
      if exists (select 1 from jsonb_object_keys(current_operation -> 'patch') key
          where not (key = any(array['id', 'ownerId', 'projectId', 'title', 'description', 'status', 'priority', 'dueAt', 'completedAt', 'archivedAt', 'orderRank']::text[])))
          or not ((current_operation -> 'patch') ?& array['id', 'ownerId', 'projectId', 'title', 'description', 'status', 'priority', 'dueAt', 'completedAt', 'archivedAt'])
          or (not (current_operation ? 'orderedCreate') and not ((current_operation -> 'patch') ? 'orderRank')) then
        raise exception 'Create contains missing or forbidden fields' using errcode = '22023';
      end if;
      if (current_operation -> 'patch' ->> 'id')::uuid
          <> (current_operation ->> 'entityId')::uuid then
        raise exception 'Create entity ID mismatch' using errcode = '22023';
      end if;
      if not ((current_operation -> 'patch' ->> 'ownerId')::uuid = auth.uid()) then
        raise exception 'Create access denied' using errcode = '42501';
      end if;
      if (current_operation -> 'patch' ->> 'ownerId')::uuid
          <> auth.uid() then
        raise exception 'Owner must match authenticated user' using errcode = '42501';
      end if;
      if (current_operation -> 'patch' -> 'status' #>> '{}') is distinct from 'todo' then
        raise exception 'Invalid initial workflow state' using errcode = '23514';
      end if;
      if ((current_operation -> 'patch' -> 'completedAt' #>> '{}')::timestamptz) is distinct from null then
        raise exception 'Invalid initial entity action state' using errcode = '23514';
      end if;
      if ((current_operation -> 'patch' -> 'archivedAt' #>> '{}')::timestamptz) is distinct from null then
        raise exception 'Invalid initial entity action state' using errcode = '23514';
      end if;
      if (current_operation -> 'patch') ? 'projectId' and jsonb_typeof(current_operation -> 'patch' -> 'projectId') <> 'null' and not (public.is_task_projects_owner((current_operation -> 'patch' ->> 'projectId')::uuid)) then
        raise exception 'Referenced entity access denied' using errcode = '42501';
      end if;
      order_scope_key := jsonb_build_array(current_operation -> 'patch' -> 'ownerId', current_operation -> 'patch' -> 'projectId')::text;
      perform pg_advisory_xact_lock(
        hashtextextended('Task:' || order_scope_key, 0)
      );
      insert into public.local_entity_order_scopes (entity_type, scope_key)
      values ('Task', order_scope_key)
      on conflict (entity_type, scope_key) do nothing;
      if current_operation ? 'orderedCreate' then
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
        where scope.entity_type = 'Task'
          and scope.scope_key = order_scope_key
        for update;
        if (current_operation -> 'orderedCreate' ->>
              'scopeBaseVersion')::bigint > current_order_scope_version then
          raise exception 'Ordered scope base version is ahead of the server'
            using errcode = '22023';
        end if;
        if current_operation -> 'orderedCreate' ->> 'placement' = 'first' then
          lower_order_rank := 0;
          select member.order_rank::numeric into upper_order_rank
          from public.tasks member
          where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.project_id is not distinct from ((current_operation -> 'patch' -> 'projectId' #>> '{}')::uuid)
          order by member.order_rank, member.id
          limit 1;
          if not found then
            upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
          end if;
        else
          upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
          select member.order_rank::numeric into lower_order_rank
          from public.tasks member
          where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.project_id is not distinct from ((current_operation -> 'patch' -> 'projectId' #>> '{}')::uuid)
          order by member.order_rank desc,
                   member.id desc
          limit 1;
          if not found then
            lower_order_rank := 0;
          end if;
        end if;
        next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
        if next_order_rank <= lower_order_rank
           or next_order_rank >= upper_order_rank then
          rebalance_window_size := 8;
          loop
            if current_operation -> 'orderedCreate' ->> 'placement' in ('first', 'before') then
              with limited as materialized (
                select member.id as member_id,
                       member.order_rank::numeric as member_rank
                from public.tasks member
                where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.project_id is not distinct from ((current_operation -> 'patch' -> 'projectId' #>> '{}')::uuid)
                order by member.order_rank, member.id
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
                115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric
              );
              rebalance_lower_rank := lower_order_rank;
            else
              with limited as materialized (
                select member.id as member_id,
                       member.order_rank::numeric as member_rank
                from public.tasks member
                where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.project_id is not distinct from ((current_operation -> 'patch' -> 'projectId' #>> '{}')::uuid)
                order by member.order_rank desc,
                         member.id desc
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
                select unnested.member_id, unnested.ordinality::numeric as position
                from unnest(rebalance_member_ids) with ordinality
                  as unnested(member_id, ordinality)
              )
              update public.tasks member
              set order_rank = lpad((
                    rebalance_lower_rank + rebalance_step *
                    (positioned.position + case
                      when current_operation -> 'orderedCreate' ->> 'placement' in ('first', 'before') then 1
                      else 0
                    end)
                  )::text, 78, '0'),
                  server_version =
                    member.server_version + 1
              from positioned
              where member.id = positioned.member_id;
              next_order_rank := rebalance_lower_rank + rebalance_step *
                case
                  when current_operation -> 'orderedCreate' ->> 'placement' in ('first', 'before') then 1
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
          end loop;
        end if;
        current_operation := jsonb_set(
          current_operation,
          '{patch,orderRank}',
          to_jsonb(lpad(next_order_rank::text, 78, '0')),
          true
        );
      end if;
      insert into public.tasks (id, owner_id, project_id, title, description, status, priority, due_at, completed_at, archived_at, order_rank)
      values ((current_operation -> 'patch' -> 'id' #>> '{}')::uuid, (current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid, (current_operation -> 'patch' -> 'projectId' #>> '{}')::uuid, current_operation -> 'patch' -> 'title' #>> '{}', current_operation -> 'patch' -> 'description' #>> '{}', current_operation -> 'patch' -> 'status' #>> '{}', current_operation -> 'patch' -> 'priority' #>> '{}', (current_operation -> 'patch' -> 'dueAt' #>> '{}')::timestamptz, (current_operation -> 'patch' -> 'completedAt' #>> '{}')::timestamptz, (current_operation -> 'patch' -> 'archivedAt' #>> '{}')::timestamptz, current_operation -> 'patch' -> 'orderRank' #>> '{}') returning * into canonical;
      update public.local_entity_order_scopes
      set version = version + 1
      where entity_type = 'Task' and scope_key = order_scope_key
      returning version into current_order_scope_version;
    elsif current_operation ->> 'operation' = 'command' then
      if current_operation ->> 'commandName' = 'setCollaborator' then
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
        if not public.is_tasks_owner(
          (current_operation ->> 'entityId')::uuid
        ) then
          raise exception 'Only the owner can manage collaborators' using errcode = '42501';
        end if;
        select * into canonical from public.tasks
        where id = (current_operation ->> 'entityId')::uuid
        for update;
        if not found then
          raise exception 'Entity not found' using errcode = 'P0002';
        end if;
        if (current_operation -> 'patch' ->> 'userId')::uuid = canonical.owner_id then
          raise exception 'Owner cannot be added as collaborator' using errcode = '22023';
        end if;
        insert into public.task_members (
          task_id,
          user_id,
          active
        ) values (
          canonical.id,
          (current_operation -> 'patch' ->> 'userId')::uuid,
          (current_operation -> 'patch' ->> 'active')::boolean
        )
        on conflict (task_id, user_id)
        do update set active = excluded.active;
        delete from public.local_entity_changes
        where entity_type = 'Task'
          and entity_id = canonical.id
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
          'Task',
          canonical.id,
          canonical.owner_id,
          canonical.server_version,
          operation_uuid,
          (current_operation -> 'patch' ->> 'userId')::uuid,
          not (current_operation -> 'patch' ->> 'active')::boolean,
          to_jsonb(canonical)
        );
      elsif current_operation ->> 'commandName' = 'moveInOrder' then
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
  if not (public.is_tasks_owner((current_operation ->> 'entityId')::uuid) or public.is_tasks_collaborator((current_operation ->> 'entityId')::uuid)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  select jsonb_build_array(owner_id, project_id)::text into order_scope_key
  from public.tasks
  where id = (current_operation ->> 'entityId')::uuid
    and deleted_at is null;
  if not found then
    raise exception 'Ordered entity not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('Task:' || order_scope_key, 0)
  );
  select candidate.* into canonical from public.tasks candidate
  where candidate.id = (current_operation ->> 'entityId')::uuid
    and candidate.deleted_at is null
    and jsonb_build_array(candidate.owner_id, candidate.project_id)::text = order_scope_key
  for update;
  if not found then
    raise exception 'Ordered entity left its canonical scope' using errcode = 'PT409';
  end if;
  insert into public.local_entity_order_scopes (entity_type, scope_key)
  values ('Task', order_scope_key)
  on conflict (entity_type, scope_key) do nothing;
  select scope.version into current_order_scope_version
  from public.local_entity_order_scopes scope
  where scope.entity_type = 'Task'
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
  if current_operation -> 'patch' ->> 'placement' = 'first' then
    lower_order_rank := 0;
    select neighbor.order_rank::numeric into upper_order_rank
    from public.tasks neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.project_id is not distinct from canonical.project_id
    order by neighbor.order_rank, neighbor.id
    limit 1;
    if not found then
      upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    end if;
  elsif current_operation -> 'patch' ->> 'placement' = 'last' then
    upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    select neighbor.order_rank::numeric into lower_order_rank
    from public.tasks neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.project_id is not distinct from canonical.project_id
    order by neighbor.order_rank desc,
             neighbor.id desc
    limit 1;
    if not found then
      lower_order_rank := 0;
    end if;
  else
    select neighbor.order_rank::numeric into anchor_order_rank
    from public.tasks neighbor
    where neighbor.id =
        (current_operation -> 'patch' ->> 'anchorId')::uuid
      and neighbor.deleted_at is null and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.project_id is not distinct from canonical.project_id;
    if not found then
      raise exception 'Ordered anchor is outside the canonical scope'
        using errcode = '22023';
    end if;
    if current_operation -> 'patch' ->> 'placement' = 'before' then
      upper_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into lower_order_rank
      from public.tasks neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.project_id is not distinct from canonical.project_id
        and (neighbor.order_rank,
             neighbor.id) <
            (lpad(anchor_order_rank::text, 78, '0'),
             (current_operation -> 'patch' ->> 'anchorId')::uuid)
      order by neighbor.order_rank desc,
               neighbor.id desc
      limit 1;
      if not found then
        lower_order_rank := 0;
      end if;
    else
      lower_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into upper_order_rank
      from public.tasks neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.project_id is not distinct from canonical.project_id
        and (neighbor.order_rank,
             neighbor.id) >
            (lpad(anchor_order_rank::text, 78, '0'),
             (current_operation -> 'patch' ->> 'anchorId')::uuid)
      order by neighbor.order_rank, neighbor.id
      limit 1;
      if not found then
        upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
      end if;
    end if;
  end if;
  next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
  if next_order_rank <= lower_order_rank or next_order_rank >= upper_order_rank then
  rebalance_window_size := 8;
  loop
    if current_operation -> 'patch' ->> 'placement' in ('first', 'before') then
      with limited as materialized (
        select member.id as member_id,
               member.order_rank::numeric as member_rank
        from public.tasks member
        where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id and member.project_id is not distinct from canonical.project_id      and member.id <>
            (current_operation ->> 'entityId')::uuid      and (current_operation -> 'patch' ->> 'placement' <> 'before' or
          (member.order_rank, member.id) >=
          (lpad(anchor_order_rank::text, 78, '0'),
           (current_operation -> 'patch' ->> 'anchorId')::uuid))
        order by member.order_rank, member.id
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
        115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric
      );
      rebalance_lower_rank := lower_order_rank;
    else
      with limited as materialized (
        select member.id as member_id,
               member.order_rank::numeric as member_rank
        from public.tasks member
        where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id and member.project_id is not distinct from canonical.project_id      and member.id <>
            (current_operation ->> 'entityId')::uuid      and (current_operation -> 'patch' ->> 'placement' <> 'after' or
          (member.order_rank, member.id) <=
          (lpad(anchor_order_rank::text, 78, '0'),
           (current_operation -> 'patch' ->> 'anchorId')::uuid))
        order by member.order_rank desc,
                 member.id desc
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
        select unnested.member_id, unnested.ordinality::numeric as position
        from unnest(rebalance_member_ids) with ordinality
          as unnested(member_id, ordinality)
      )
      update public.tasks member
      set order_rank = lpad((
            rebalance_lower_rank + rebalance_step *
            (positioned.position + case
              when current_operation -> 'patch' ->> 'placement' in ('first', 'before') then 1
              else 0
            end)
          )::text, 78, '0'),
          server_version =
            member.server_version + 1
      from positioned
      where member.id = positioned.member_id;
      next_order_rank := rebalance_lower_rank + rebalance_step *
        case
          when current_operation -> 'patch' ->> 'placement' in ('first', 'before') then 1
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
  end loop;
  end if;
  update public.tasks
  set order_rank = lpad(next_order_rank::text, 78, '0'),
      server_version =
        server_version + 1
  where id = canonical.id
  returning * into canonical;
  update public.local_entity_order_scopes scope
  set version = scope.version + 1
  where scope.entity_type = 'Task'
    and scope.scope_key = order_scope_key
  returning scope.version into current_order_scope_version;
      elsif current_operation ->> 'commandName' = 'transferInOrder' then
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
     or jsonb_typeof(current_operation -> 'patch' -> 'targetScope' -> 'projectId') not in ('string', 'null') then
    raise exception 'Ordered transfer has invalid field types' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(current_operation -> 'patch' -> 'targetScope') key
    where not (key = any(array['projectId']::text[]))
  ) or not ((current_operation -> 'patch' -> 'targetScope') ?&
      array['projectId']) then
    raise exception 'Ordered transfer target scope is incomplete' using errcode = '22023';
  end if;
  if not (public.is_tasks_owner((current_operation ->> 'entityId')::uuid) or public.is_tasks_collaborator((current_operation ->> 'entityId')::uuid)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  select * into canonical
  from public.tasks
  where id = (current_operation ->> 'entityId')::uuid
    and deleted_at is null;
  if not found then
    raise exception 'Ordered entity not found' using errcode = 'P0002';
  end if;
  source_order_scope_key := jsonb_build_array(canonical.owner_id, canonical.project_id)::text;
  target_order_scope_key := jsonb_build_array(canonical.owner_id, current_operation -> 'patch' -> 'targetScope' -> 'projectId')::text;
  if source_order_scope_key = target_order_scope_key then
    raise exception 'Ordered transfer must change scope' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('Task:' || least(source_order_scope_key, target_order_scope_key), 0)
  );
  perform pg_advisory_xact_lock(
    hashtextextended('Task:' || greatest(source_order_scope_key, target_order_scope_key), 0)
  );
  select candidate.* into canonical
  from public.tasks candidate
  where candidate.id = (current_operation ->> 'entityId')::uuid
    and candidate.deleted_at is null
    and jsonb_build_array(candidate.owner_id, candidate.project_id)::text = source_order_scope_key
  for update;
  if not found then
    raise exception 'Ordered entity left its source scope' using errcode = 'PT409';
  end if;
  if (current_operation -> 'patch' -> 'targetScope') ? 'projectId' and jsonb_typeof(current_operation -> 'patch' -> 'targetScope' -> 'projectId') <> 'null' and not (public.is_task_projects_owner((current_operation -> 'patch' -> 'targetScope' ->> 'projectId')::uuid)) then
    raise exception 'Referenced entity access denied' using errcode = '42501';
  end if;
  source_order_scope := jsonb_build_object('ownerId', canonical.owner_id, 'projectId', canonical.project_id);
  target_order_scope := jsonb_build_object('ownerId', canonical.owner_id, 'projectId', (current_operation -> 'patch' -> 'targetScope' -> 'projectId' #>> '{}')::uuid);
  insert into public.local_entity_order_scopes (entity_type, scope_key)
  values
    ('Task', source_order_scope_key),
    ('Task', target_order_scope_key)
  on conflict (entity_type, scope_key) do nothing;
  select scope.version into source_order_scope_version
  from public.local_entity_order_scopes scope
  where scope.entity_type = 'Task'
    and scope.scope_key = source_order_scope_key
  for update;
  select scope.version into target_order_scope_version
  from public.local_entity_order_scopes scope
  where scope.entity_type = 'Task'
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
    select member.order_rank::numeric into upper_order_rank
    from public.tasks member
    where member.deleted_at is null
      and member.owner_id is not distinct from canonical.owner_id and member.project_id is not distinct from ((current_operation -> 'patch' -> 'targetScope' -> 'projectId' #>> '{}')::uuid)
    order by member.order_rank, member.id
    limit 1;
    if not found then upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric; end if;
  else
    upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    select member.order_rank::numeric into lower_order_rank
    from public.tasks member
    where member.deleted_at is null
      and member.owner_id is not distinct from canonical.owner_id and member.project_id is not distinct from ((current_operation -> 'patch' -> 'targetScope' -> 'projectId' #>> '{}')::uuid)
    order by member.order_rank desc, member.id desc
    limit 1;
    if not found then lower_order_rank := 0; end if;
  end if;
  next_order_rank := trunc((lower_order_rank + upper_order_rank) / 2);
  if next_order_rank <= lower_order_rank or next_order_rank >= upper_order_rank then
  rebalance_window_size := 8;
  loop
    if current_operation -> 'patch' ->> 'placement' in ('first', 'before') then
      with limited as materialized (
        select member.id as member_id,
               member.order_rank::numeric as member_rank
        from public.tasks member
        where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id and member.project_id is not distinct from ((current_operation -> 'patch' -> 'targetScope' -> 'projectId' #>> '{}')::uuid)      and member.id <>
            (current_operation ->> 'entityId')::uuid
        order by member.order_rank, member.id
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
        115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric
      );
      rebalance_lower_rank := lower_order_rank;
    else
      with limited as materialized (
        select member.id as member_id,
               member.order_rank::numeric as member_rank
        from public.tasks member
        where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id and member.project_id is not distinct from ((current_operation -> 'patch' -> 'targetScope' -> 'projectId' #>> '{}')::uuid)      and member.id <>
            (current_operation ->> 'entityId')::uuid
        order by member.order_rank desc,
                 member.id desc
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
        select unnested.member_id, unnested.ordinality::numeric as position
        from unnest(rebalance_member_ids) with ordinality
          as unnested(member_id, ordinality)
      )
      update public.tasks member
      set order_rank = lpad((
            rebalance_lower_rank + rebalance_step *
            (positioned.position + case
              when current_operation -> 'patch' ->> 'placement' in ('first', 'before') then 1
              else 0
            end)
          )::text, 78, '0'),
          server_version =
            member.server_version + 1
      from positioned
      where member.id = positioned.member_id;
      next_order_rank := rebalance_lower_rank + rebalance_step *
        case
          when current_operation -> 'patch' ->> 'placement' in ('first', 'before') then 1
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
  end loop;
  end if;
  update public.tasks
  set project_id = (current_operation -> 'patch' -> 'targetScope' -> 'projectId' #>> '{}')::uuid,
      order_rank = lpad(next_order_rank::text, 78, '0'),
      server_version = canonical.server_version + 1
  where id = canonical.id
  returning * into canonical;
  update public.local_entity_order_scopes scope
  set version = scope.version + 1
  where scope.entity_type = 'Task'
    and scope.scope_key = source_order_scope_key
  returning scope.version into source_order_scope_version;
  update public.local_entity_order_scopes scope
  set version = scope.version + 1
  where scope.entity_type = 'Task'
    and scope.scope_key = target_order_scope_key
  returning scope.version into target_order_scope_version;
  order_scope_versions := jsonb_build_array(
    jsonb_build_object('scope', source_order_scope, 'version', source_order_scope_version),
    jsonb_build_object('scope', target_order_scope, 'version', target_order_scope_version)
  );
  current_order_scope_version := null;
      else
        raise exception 'Unsupported command' using errcode = '22023';
      end if;
    elsif current_operation ->> 'operation' in ('patch', 'delete') then
      if current_operation -> 'patch' ?| array['deletedAt'] then
        if current_operation ->> 'operation' = 'delete'
           and not (public.is_tasks_owner((current_operation ->> 'entityId')::uuid)) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        if current_operation ->> 'operation' = 'patch'
           and not (public.is_tasks_owner((current_operation ->> 'entityId')::uuid) or public.is_tasks_collaborator((current_operation ->> 'entityId')::uuid)) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        select jsonb_build_array(candidate.owner_id, candidate.project_id)::text,
               (candidate.deleted_at is null) <>
                 (case
      when current_operation -> 'patch' ? 'deletedAt' then
        current_operation -> 'patch' -> 'deletedAt' = 'null'::jsonb
      else candidate.deleted_at is null
    end)
        into order_scope_key, order_scope_membership_changed
        from public.tasks candidate
        where candidate.id =
          (current_operation ->> 'entityId')::uuid;
        if not found then
          raise exception 'Entity not found' using errcode = 'P0002';
        end if;
        if order_scope_membership_changed then
          perform pg_advisory_xact_lock(
            hashtextextended('Task:' || order_scope_key, 0)
          );
          insert into public.local_entity_order_scopes (entity_type, scope_key)
          values ('Task', order_scope_key)
          on conflict (entity_type, scope_key) do nothing;
          select scope.version into current_order_scope_version
          from public.local_entity_order_scopes scope
          where scope.entity_type = 'Task'
            and scope.scope_key = order_scope_key
          for update;
        end if;
      end if;
      canonical := public.apply_tasks_patch(
        (current_operation ->> 'entityId')::uuid,
        (current_operation ->> 'baseServerVersion')::bigint,
        current_operation ->> 'operation',
        current_operation -> 'patch');
      if order_scope_membership_changed then
        update public.local_entity_order_scopes
        set version = version + 1
        where entity_type = 'Task' and scope_key = order_scope_key
        returning version into current_order_scope_version;
      end if;
    end if;
    select changes.sequence into change_sequence from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.entity_type = 'Task' and changes.entity_id = canonical.id order by changes.sequence desc limit 1;
    if change_sequence is null then
      raise exception 'Accepted operation has no change-log entry' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('entityType', changes.entity_type, 'record', changes.record, 'sequence', changes.sequence, 'operationId', changes.operation_id, 'serverVersion', changes.server_version) order by changes.sequence), '[]'::jsonb) into related_changes from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.audience_user_id is null and not changes.is_revocation and not (changes.entity_type = 'Task' and changes.entity_id = canonical.id);
    if current_order_scope_version is not null then
      order_scope_versions := jsonb_build_array(
        jsonb_build_object('scope', jsonb_build_object('ownerId', canonical.owner_id, 'projectId', canonical.project_id), 'version', current_order_scope_version)
      );
    end if;
    receipt_result := jsonb_build_object('record', to_jsonb(canonical), 'sequence', change_sequence, 'operationId', operation_uuid, 'serverVersion', canonical.server_version, 'scopeVersions', order_scope_versions, 'relatedChanges', related_changes);
    insert into public.local_entity_operation_receipts (operation_id, user_id, entity_type, entity_id, result) values (operation_uuid, auth.uid(), 'Task', canonical.id, receipt_result);
    results := results || jsonb_build_array(receipt_result);
  end loop;
  return results;
end;
$function$
;


