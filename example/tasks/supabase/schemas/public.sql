-- GENERATED FILE. DO NOT EDIT.
-- Source: package:tasks_example/nodus.lock
-- Sync target: supabase
-- The target descriptor subgraph is the source of truth for this public schema fragment.

-- GENERATED FILE. DO NOT EDIT.
-- Source: package:tasks_example/features/tasks/domain/task_project.dart
-- Entity declarations are the schema source of truth.

create table if not exists public.task_projects (
  id uuid not null primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (title = btrim(title)) check (char_length(btrim(title)) >= 1) check (char_length(title) <= 80),
  order_rank text not null default '057896044618658097711785492504343953926634992332820282019728792003956564819967' check (order_rank ~ '^[0-9]{78}$' and order_rank::numeric > 0 and order_rank::numeric < 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric),
  deleted_at timestamptz,
  server_version bigint not null default 1
);

create index if not exists task_projects_owner_id_deleted_at_order_rank_id_idx on public.task_projects (owner_id, deleted_at, order_rank, id);
create index if not exists task_projects_owner_id_deleted_at_title_id_idx on public.task_projects (owner_id, deleted_at, title, id);

create or replace function public.is_task_projects_owner(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.task_projects entity where entity.id = p_id and entity.owner_id = auth.uid());
$$;
create or replace function public.is_task_projects_collaborator(p_id uuid)
returns boolean language sql immutable security definer
set search_path = '' as $$ select false; $$;
revoke all on function public.is_task_projects_owner(uuid) from public, anon, authenticated, service_role;
revoke all on function public.is_task_projects_collaborator(uuid) from public, anon, authenticated, service_role;
grant execute on function public.is_task_projects_owner(uuid) to authenticated;
grant execute on function public.is_task_projects_collaborator(uuid) to authenticated;

alter table public.task_projects enable row level security;
drop policy if exists task_projects_select_owner on public.task_projects;
create policy task_projects_select_owner on public.task_projects for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists task_projects_insert_owner on public.task_projects;
create policy task_projects_insert_owner on public.task_projects for insert to authenticated with check ((select auth.uid()) = owner_id);
drop policy if exists task_projects_update_owner on public.task_projects;
create policy task_projects_update_owner on public.task_projects for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
drop policy if exists task_projects_delete_owner on public.task_projects;
create policy task_projects_delete_owner on public.task_projects for delete to authenticated using ((select auth.uid()) = owner_id);
revoke all on public.task_projects from anon;
revoke all on public.task_projects from authenticated;
grant select on public.task_projects to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_projects') then
    alter publication supabase_realtime add table public.task_projects;
  end if;
end;
$$;


create table if not exists public.local_entity_operation_receipts (
  operation_id uuid not null,
  user_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  result jsonb not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, operation_id)
);
alter table public.local_entity_operation_receipts enable row level security;
drop policy if exists local_entity_receipts_owner on public.local_entity_operation_receipts;
create policy local_entity_receipts_owner on public.local_entity_operation_receipts for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
revoke all on public.local_entity_operation_receipts from anon, authenticated;

create table if not exists public.local_entity_order_scopes (
  entity_type text not null,
  scope_key text not null,
  version bigint not null default 0 check (version >= 0),
  primary key (entity_type, scope_key)
);
alter table public.local_entity_order_scopes enable row level security;
revoke all on public.local_entity_order_scopes from anon, authenticated;

create table if not exists public.local_entity_changes (
  sequence bigint generated always as identity primary key,
  entity_type text not null,
  entity_id uuid not null,
  owner_id uuid not null,
  server_version bigint not null,
  operation_id uuid,
  written_by uuid default auth.uid(),
  audience_user_id uuid,
  is_revocation boolean not null default false,
  record jsonb not null,
  changed_at timestamptz not null default now()
);
create index if not exists local_entity_changes_type_sequence_idx on public.local_entity_changes (entity_type, sequence);
create index if not exists local_entity_changes_identity_idx on public.local_entity_changes (entity_type, entity_id, audience_user_id, sequence);
create index if not exists local_entity_changes_operation_idx on public.local_entity_changes (operation_id, written_by, sequence) where operation_id is not null;
create index if not exists local_entity_changes_owner_idx on public.local_entity_changes (owner_id);
create index if not exists local_entity_changes_audience_idx on public.local_entity_changes (audience_user_id) where audience_user_id is not null;
alter table public.local_entity_changes enable row level security;
revoke all on public.local_entity_changes from anon, authenticated;
grant select on public.local_entity_changes to authenticated;
drop policy if exists local_entity_changes_select_audience on public.local_entity_changes;
create policy local_entity_changes_select_audience on public.local_entity_changes for select to authenticated using (audience_user_id = (select auth.uid()));
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'local_entity_changes') then
    alter publication supabase_realtime add table public.local_entity_changes;
  end if;
end;
$$;

create or replace function public.serialize_local_entity_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nodus.local_entity_changes', 0));
  return null;
end;
$$;
revoke all on function public.serialize_local_entity_changes() from public, anon, authenticated, service_role;
drop trigger if exists local_entity_changes_serialize on public.local_entity_changes;
create trigger local_entity_changes_serialize before insert on public.local_entity_changes for each statement execute function public.serialize_local_entity_changes();

create table if not exists public.local_entity_change_recipients (
  user_id uuid not null references auth.users (id) on delete cascade,
  sequence bigint not null references public.local_entity_changes (sequence) on delete cascade,
  primary key (user_id, sequence)
);
create index if not exists local_entity_change_recipients_sequence_idx on public.local_entity_change_recipients (sequence);
alter table public.local_entity_change_recipients enable row level security;
revoke all on public.local_entity_change_recipients from anon, authenticated;

create or replace function public.capture_task_projects_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.local_entity_changes where entity_type = 'TaskProject' and entity_id = new.id and audience_user_id is null;
  insert into public.local_entity_changes (entity_type, entity_id, owner_id, server_version, operation_id, audience_user_id, is_revocation, record)
  values ('TaskProject', new.id, new.owner_id, new.server_version, nullif(current_setting('app.operation_id', true), '')::uuid, null, false, to_jsonb(new));
  return new;
end;
$$;
revoke all on function public.capture_task_projects_change() from public, anon, authenticated, service_role;
drop trigger if exists task_projects_capture_change on public.task_projects;
create trigger task_projects_capture_change after insert or update on public.task_projects for each row execute function public.capture_task_projects_change();

create or replace function public.upcast_task_projects_operation(p_operation jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  current_version integer;
begin
  current_version := coalesce((p_operation ->> 'protocolVersion')::integer, 0);
  if current_version < 1 or current_version > 2 then
    raise exception 'Unsupported protocol version' using errcode = '22023';
  end if;
  if jsonb_typeof(p_operation -> 'patch') <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;
  if current_version < 2 then
    if p_operation ->> 'operation' = 'create' and not ((p_operation -> 'patch') ? 'orderRank') then
      p_operation := jsonb_set(p_operation, '{patch,orderRank}', '"057896044618658097711785492504343953926634992332820282019728792003956564819967"'::jsonb, true);
    end if;
    p_operation := jsonb_set(p_operation, '{protocolVersion}', '2'::jsonb, true);
    current_version := 2;
  end if;
  return p_operation;
end;
$$;

create or replace function public.apply_task_projects_patch(
  p_id uuid,
  p_base_server_version bigint,
  p_operation text,
  p_patch jsonb
) returns public.task_projects
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

create or replace function public.push_task_projects_operations(p_operations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if public.is_agent_request() and not public.agent_writable('TaskProject') then
    raise exception 'Agents cannot change this entity' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_session_active() then
    raise exception 'Agent access was revoked' using errcode = '42501';
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
    select changes.sequence into change_sequence from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() and changes.entity_type = 'TaskProject' and changes.entity_id = canonical.id order by changes.sequence desc limit 1;
    if change_sequence is null then
      raise exception 'Accepted operation has no change-log entry' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('entityType', changes.entity_type, 'record', changes.record, 'sequence', changes.sequence, 'operationId', changes.operation_id, 'serverVersion', changes.server_version) order by changes.sequence), '[]'::jsonb) into related_changes from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() and changes.audience_user_id is null and not changes.is_revocation and not (changes.entity_type = 'TaskProject' and changes.entity_id = canonical.id);
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
$$;

revoke all on function public.upcast_task_projects_operation(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.apply_task_projects_patch(uuid, bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.push_task_projects_operations(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.push_task_projects_operations(jsonb) to authenticated;

-- GENERATED FILE. DO NOT EDIT.
-- Source: package:tasks_example/features/tasks/domain/task.dart
-- Entity declarations are the schema source of truth.

create table if not exists public.tasks (
  id uuid not null primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  project_id uuid references public.task_projects (id) on delete set null deferrable initially deferred,
  title text not null check (title = btrim(title)) check (char_length(btrim(title)) >= 1) check (char_length(title) <= 160),
  description text check (description is null or (description = btrim(description) and char_length(description) > 0)) check (char_length(description) <= 1000),
  status text not null default 'todo' check (status in ('todo', 'in_progress', 'done')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high')),
  due_at timestamptz,
  completed_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  order_rank text not null default '057896044618658097711785492504343953926634992332820282019728792003956564819967' check (order_rank ~ '^[0-9]{78}$' and order_rank::numeric > 0 and order_rank::numeric < 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric),
  deleted_at timestamptz,
  server_version bigint not null default 1
);

create index if not exists tasks_owner_id_project_id_deleted_at_order_rank_id_idx on public.tasks (owner_id, project_id, deleted_at, order_rank, id);
create index if not exists tasks_project_id_idx on public.tasks (project_id);
create index if not exists tasks_owner_id_archived_at_idx on public.tasks (owner_id, archived_at);
create index if not exists tasks_owner_id_project_id_archived_at_dele_01d92b15705390c6_idx on public.tasks (owner_id, project_id, archived_at, deleted_at, status, due_at, id);
create index if not exists tasks_owner_id_project_id_archived_at_deleted_at_id_idx on public.tasks (owner_id, project_id, archived_at, deleted_at, id);

create table if not exists public.task_members (
  task_id uuid not null references public.tasks (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  active boolean not null default true,
  primary key (task_id, user_id)
);
alter table public.task_members enable row level security;

create or replace function public.is_tasks_owner(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.tasks entity where entity.id = p_id and entity.owner_id = auth.uid());
$$;
drop policy if exists task_members_select on public.task_members;
drop policy if exists task_members_owner_insert on public.task_members;
drop policy if exists task_members_owner_update on public.task_members;
drop policy if exists task_members_owner_delete on public.task_members;
create or replace function public.is_tasks_collaborator(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.task_members member where member.task_id = p_id and member.user_id = auth.uid() and member.active);
$$;
revoke all on function public.is_tasks_owner(uuid) from public, anon, authenticated, service_role;
revoke all on function public.is_tasks_collaborator(uuid) from public, anon, authenticated, service_role;
grant execute on function public.is_tasks_owner(uuid) to authenticated;
grant execute on function public.is_tasks_collaborator(uuid) to authenticated;
create policy task_members_select on public.task_members for select to authenticated using (user_id = (select auth.uid()) or public.is_tasks_owner(task_id));
create policy task_members_owner_insert on public.task_members for insert to authenticated with check (public.is_tasks_owner(task_id));
create policy task_members_owner_update on public.task_members for update to authenticated using (public.is_tasks_owner(task_id)) with check (public.is_tasks_owner(task_id));
create policy task_members_owner_delete on public.task_members for delete to authenticated using (public.is_tasks_owner(task_id));
revoke all on public.task_members from anon;
revoke all on public.task_members from authenticated;
grant select on public.task_members to authenticated;

alter table public.tasks enable row level security;
drop policy if exists tasks_select_owner on public.tasks;
create policy tasks_select_owner on public.tasks for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists tasks_insert_owner on public.tasks;
create policy tasks_insert_owner on public.tasks for insert to authenticated with check ((select auth.uid()) = owner_id);
drop policy if exists tasks_update_owner on public.tasks;
create policy tasks_update_owner on public.tasks for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
drop policy if exists tasks_delete_owner on public.tasks;
create policy tasks_delete_owner on public.tasks for delete to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists tasks_select_collaborator on public.tasks;
create policy tasks_select_collaborator on public.tasks for select to authenticated using (public.is_tasks_collaborator(tasks.id));
drop policy if exists tasks_update_collaborator on public.tasks;
create policy tasks_update_collaborator on public.tasks for update to authenticated using (public.is_tasks_collaborator(tasks.id)) with check (public.is_tasks_collaborator(tasks.id));
revoke all on public.tasks from anon;
revoke all on public.tasks from authenticated;
grant select on public.tasks to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tasks') then
    alter publication supabase_realtime add table public.tasks;
  end if;
end;
$$;
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'task_members'
     ) then
    alter publication supabase_realtime add table public.task_members;
  end if;
end;
$$;

create or replace function public.capture_tasks_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.local_entity_changes where entity_type = 'Task' and entity_id = new.id and audience_user_id is null;
  insert into public.local_entity_changes (entity_type, entity_id, owner_id, server_version, operation_id, audience_user_id, is_revocation, record)
  values ('Task', new.id, new.owner_id, new.server_version, nullif(current_setting('app.operation_id', true), '')::uuid, null, false, to_jsonb(new));
  return new;
end;
$$;
revoke all on function public.capture_tasks_change() from public, anon, authenticated, service_role;
drop trigger if exists tasks_capture_change on public.tasks;
create trigger tasks_capture_change after insert or update on public.tasks for each row execute function public.capture_tasks_change();

create or replace function public.upcast_tasks_operation(p_operation jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  current_version integer;
begin
  current_version := coalesce((p_operation ->> 'protocolVersion')::integer, 0);
  if current_version < 1 or current_version > 3 then
    raise exception 'Unsupported protocol version' using errcode = '22023';
  end if;
  if jsonb_typeof(p_operation -> 'patch') <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;
  if current_version < 2 then
    if p_operation ->> 'operation' = 'create' and not ((p_operation -> 'patch') ? 'orderRank') then
      p_operation := jsonb_set(p_operation, '{patch,orderRank}', '"057896044618658097711785492504343953926634992332820282019728792003956564819967"'::jsonb, true);
    end if;
    p_operation := jsonb_set(p_operation, '{protocolVersion}', '2'::jsonb, true);
    current_version := 2;
  end if;
  if current_version < 3 then
    p_operation := jsonb_set(p_operation, '{protocolVersion}', '3'::jsonb, true);
    current_version := 3;
  end if;
  return p_operation;
end;
$$;

create or replace function public.apply_tasks_patch(
  p_id uuid,
  p_base_server_version bigint,
  p_operation text,
  p_patch jsonb
) returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
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
  if current_row.server_version <> p_base_server_version then
    raise exception 'Version conflict' using errcode = 'PT409';
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
$$;

create or replace function public.push_tasks_operations(p_operations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if public.is_agent_request() and not public.agent_writable('Task') then
    raise exception 'Agents cannot change this entity' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_session_active() then
    raise exception 'Agent access was revoked' using errcode = '42501';
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
    select changes.sequence into change_sequence from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() and changes.entity_type = 'Task' and changes.entity_id = canonical.id order by changes.sequence desc limit 1;
    if change_sequence is null then
      raise exception 'Accepted operation has no change-log entry' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('entityType', changes.entity_type, 'record', changes.record, 'sequence', changes.sequence, 'operationId', changes.operation_id, 'serverVersion', changes.server_version) order by changes.sequence), '[]'::jsonb) into related_changes from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() and changes.audience_user_id is null and not changes.is_revocation and not (changes.entity_type = 'Task' and changes.entity_id = canonical.id);
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
$$;

revoke all on function public.upcast_tasks_operation(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.apply_tasks_patch(uuid, bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.push_tasks_operations(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.push_tasks_operations(jsonb) to authenticated;

-- GENERATED FILE. DO NOT EDIT.
-- Source: package:tasks_example/features/tasks/domain/task_activity.dart
-- Entity declarations are the schema source of truth.

create table if not exists public.task_activities (
  id uuid not null primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  subject_id uuid not null,
  actor_id uuid not null,
  operation text not null check (char_length(btrim(operation)) >= 1) check (char_length(operation) <= 160),
  label text not null check (char_length(btrim(label)) >= 1) check (char_length(label) <= 240),
  source_operation_id text not null check (char_length(btrim(source_operation_id)) >= 1) check (char_length(source_operation_id) <= 64),
  occurred_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 1
);

create index if not exists task_activities_subject_id_occurred_at_idx on public.task_activities (subject_id, occurred_at);
create index if not exists task_activities_occurred_at_idx on public.task_activities (occurred_at);
create unique index if not exists task_activities_source_operation_id_active_idx on public.task_activities (source_operation_id) where deleted_at is null;

create or replace function public.is_task_activities_owner(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.task_activities entity where entity.id = p_id and entity.owner_id = auth.uid());
$$;
create or replace function public.is_task_activities_collaborator(p_id uuid)
returns boolean language sql immutable security definer
set search_path = '' as $$ select false; $$;
revoke all on function public.is_task_activities_owner(uuid) from public, anon, authenticated, service_role;
revoke all on function public.is_task_activities_collaborator(uuid) from public, anon, authenticated, service_role;
grant execute on function public.is_task_activities_owner(uuid) to authenticated;
grant execute on function public.is_task_activities_collaborator(uuid) to authenticated;

alter table public.task_activities enable row level security;
drop policy if exists task_activities_select_source on public.task_activities;
create policy task_activities_select_source on public.task_activities for select to authenticated using ((task_activities.owner_id = (select source.owner_id from public.tasks source where source.id = task_activities.subject_id)) and (public.is_tasks_owner(task_activities.subject_id) or public.is_tasks_collaborator(task_activities.subject_id)));
drop policy if exists task_activities_insert_source_operation on public.task_activities;
create policy task_activities_insert_source_operation on public.task_activities for insert to authenticated with check ((task_activities.actor_id = auth.uid()) and (task_activities.owner_id = (select source.owner_id from public.tasks source where source.id = task_activities.subject_id)) and (public.is_tasks_owner(task_activities.subject_id) or public.is_tasks_collaborator(task_activities.subject_id)));
revoke all on public.task_activities from anon;
revoke all on public.task_activities from authenticated;
grant select on public.task_activities to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_activities') then
    alter publication supabase_realtime add table public.task_activities;
  end if;
end;
$$;


create or replace function public.capture_task_activities_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.local_entity_changes where entity_type = 'TaskActivity' and entity_id = new.id and audience_user_id is null;
  insert into public.local_entity_changes (entity_type, entity_id, owner_id, server_version, operation_id, audience_user_id, is_revocation, record)
  values ('TaskActivity', new.id, new.owner_id, new.server_version, nullif(current_setting('app.operation_id', true), '')::uuid, null, false, to_jsonb(new));
  return new;
end;
$$;
revoke all on function public.capture_task_activities_change() from public, anon, authenticated, service_role;
drop trigger if exists task_activities_capture_change on public.task_activities;
create trigger task_activities_capture_change after insert or update on public.task_activities for each row execute function public.capture_task_activities_change();

create or replace function public.upcast_task_activities_operation(p_operation jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  current_version integer;
begin
  current_version := coalesce((p_operation ->> 'protocolVersion')::integer, 0);
  if current_version < 1 or current_version > 1 then
    raise exception 'Unsupported protocol version' using errcode = '22023';
  end if;
  if jsonb_typeof(p_operation -> 'patch') <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;
  return p_operation;
end;
$$;

create or replace function public.push_task_activities_operations(p_operations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_operation jsonb;
  operation_uuid uuid;
  receipt_result jsonb;
  canonical public.task_activities;
  change_sequence bigint;
  results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_writable('TaskActivity') then
    raise exception 'Agents cannot change this entity' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_session_active() then
    raise exception 'Agent access was revoked' using errcode = '42501';
  end if;
  if jsonb_typeof(p_operations) <> 'array' then
    raise exception 'Operations must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'At most 100 operations are allowed per batch' using errcode = '22023';
  end if;
  for current_operation in select value from jsonb_array_elements(p_operations) loop
    current_operation := public.upcast_task_activities_operation(current_operation);
    operation_uuid := (current_operation ->> 'operationId')::uuid;
    if current_operation ->> 'entityType' <> 'TaskActivity' then
      raise exception 'Unexpected entity type' using errcode = '22023';
    end if;
    if coalesce((current_operation ->> 'protocolVersion')::integer, 0) <> 1 then
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
    if current_operation ->> 'operation' not in ('create') then
      raise exception 'Unsupported operation' using errcode = '22023';
    end if;
    if current_operation ->> 'operation' = 'create' then
      if exists (select 1 from jsonb_object_keys(current_operation -> 'patch') key
          where not (key = any(array['id', 'ownerId', 'subjectId', 'actorId', 'operation', 'label', 'sourceOperationId', 'occurredAt', 'deletedAt']::text[])))
          or not ((current_operation -> 'patch') ?& array['id', 'ownerId', 'subjectId', 'actorId', 'operation', 'label', 'sourceOperationId', 'occurredAt', 'deletedAt']) then
        raise exception 'Create contains missing or forbidden fields' using errcode = '22023';
      end if;
      if (current_operation -> 'patch' ->> 'id')::uuid
          <> (current_operation ->> 'entityId')::uuid then
        raise exception 'Create entity ID mismatch' using errcode = '22023';
      end if;
      if not (((current_operation -> 'patch' ->> 'actorId')::uuid = auth.uid()) and ((current_operation -> 'patch' ->> 'ownerId')::uuid = (select source.owner_id from public.tasks source where source.id = (current_operation -> 'patch' ->> 'subjectId')::uuid)) and (exists (select 1 from public.local_entity_operation_receipts source_receipt where source_receipt.entity_type = 'Task' and source_receipt.entity_id = (current_operation -> 'patch' ->> 'subjectId')::uuid and source_receipt.user_id = (current_operation -> 'patch' ->> 'actorId')::uuid and source_receipt.operation_id = (current_operation -> 'patch' ->> 'sourceOperationId')::uuid))) then
        raise exception 'Create access denied' using errcode = '42501';
      end if;


      insert into public.task_activities (id, owner_id, subject_id, actor_id, operation, label, source_operation_id, occurred_at, deleted_at)
      values ((current_operation -> 'patch' -> 'id' #>> '{}')::uuid, (current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid, (current_operation -> 'patch' -> 'subjectId' #>> '{}')::uuid, (current_operation -> 'patch' -> 'actorId' #>> '{}')::uuid, current_operation -> 'patch' -> 'operation' #>> '{}', current_operation -> 'patch' -> 'label' #>> '{}', current_operation -> 'patch' -> 'sourceOperationId' #>> '{}', (current_operation -> 'patch' -> 'occurredAt' #>> '{}')::timestamptz, (current_operation -> 'patch' -> 'deletedAt' #>> '{}')::timestamptz) returning * into canonical;
    end if;
    select changes.sequence into change_sequence from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() order by changes.sequence desc limit 1;
    if change_sequence is null then
      raise exception 'Accepted operation has no change-log entry' using errcode = 'P0001';
    end if;
    receipt_result := jsonb_build_object('record', to_jsonb(canonical), 'sequence', change_sequence, 'operationId', operation_uuid, 'serverVersion', canonical.server_version);
    insert into public.local_entity_operation_receipts (operation_id, user_id, entity_type, entity_id, result) values (operation_uuid, auth.uid(), 'TaskActivity', canonical.id, receipt_result);
    results := results || jsonb_build_array(receipt_result);
  end loop;
  return results;
end;
$$;

revoke all on function public.upcast_task_activities_operation(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.push_task_activities_operations(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.push_task_activities_operations(jsonb) to authenticated;

-- GENERATED FILE. DO NOT EDIT.
-- Source: package:tasks_example/features/tasks/domain/task_step.dart
-- Entity declarations are the schema source of truth.

create table if not exists public.task_steps (
  id uuid not null primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  task_id uuid not null references public.tasks (id) on delete cascade deferrable initially deferred,
  title text not null check (char_length(btrim(title)) >= 1) check (char_length(title) <= 160),
  done boolean not null default false,
  order_rank text not null default '057896044618658097711785492504343953926634992332820282019728792003956564819967' check (order_rank ~ '^[0-9]{78}$' and order_rank::numeric > 0 and order_rank::numeric < 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric),
  deleted_at timestamptz,
  server_version bigint not null default 1
);

create index if not exists task_steps_owner_id_task_id_deleted_at_order_rank_id_idx on public.task_steps (owner_id, task_id, deleted_at, order_rank, id);
create index if not exists task_steps_task_id_idx on public.task_steps (task_id);
create unique index if not exists task_steps_task_id_title_active_idx on public.task_steps (task_id, title) where deleted_at is null;

create or replace function public.is_task_steps_owner(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.task_steps entity where entity.id = p_id and entity.owner_id = auth.uid());
$$;
create or replace function public.is_task_steps_collaborator(p_id uuid)
returns boolean language sql immutable security definer
set search_path = '' as $$ select false; $$;
revoke all on function public.is_task_steps_owner(uuid) from public, anon, authenticated, service_role;
revoke all on function public.is_task_steps_collaborator(uuid) from public, anon, authenticated, service_role;
grant execute on function public.is_task_steps_owner(uuid) to authenticated;
grant execute on function public.is_task_steps_collaborator(uuid) to authenticated;

create or replace function public.is_task_steps_reference(p_id uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.task_steps entity where entity.id = p_id and (((public.is_tasks_owner(entity.task_id) or public.is_tasks_collaborator(entity.task_id))) and ((entity.owner_id = (select target.owner_id from public.tasks target where target.id = entity.task_id)))));
$$;
revoke all on function public.is_task_steps_reference(uuid) from public, anon, authenticated, service_role;
grant execute on function public.is_task_steps_reference(uuid) to authenticated;

alter table public.task_steps enable row level security;
drop policy if exists task_steps_select_owner on public.task_steps;
create policy task_steps_select_owner on public.task_steps for select to authenticated using (((select auth.uid()) = owner_id) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_insert_owner on public.task_steps;
create policy task_steps_insert_owner on public.task_steps for insert to authenticated with check (((select auth.uid()) = owner_id) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_update_owner on public.task_steps;
create policy task_steps_update_owner on public.task_steps for update to authenticated using (((select auth.uid()) = owner_id) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id)))) with check (((select auth.uid()) = owner_id) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_delete_owner on public.task_steps;
create policy task_steps_delete_owner on public.task_steps for delete to authenticated using (((select auth.uid()) = owner_id) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_select_reference on public.task_steps;
create policy task_steps_select_reference on public.task_steps for select to authenticated using (((public.is_tasks_owner(task_steps.task_id) or public.is_tasks_collaborator(task_steps.task_id))) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_insert_reference on public.task_steps;
create policy task_steps_insert_reference on public.task_steps for insert to authenticated with check (((public.is_tasks_owner(task_steps.task_id) or public.is_tasks_collaborator(task_steps.task_id))) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_update_reference on public.task_steps;
create policy task_steps_update_reference on public.task_steps for update to authenticated using (((public.is_tasks_owner(task_steps.task_id) or public.is_tasks_collaborator(task_steps.task_id))) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id)))) with check (((public.is_tasks_owner(task_steps.task_id) or public.is_tasks_collaborator(task_steps.task_id))) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
drop policy if exists task_steps_delete_reference on public.task_steps;
create policy task_steps_delete_reference on public.task_steps for delete to authenticated using (((public.is_tasks_owner(task_steps.task_id) or public.is_tasks_collaborator(task_steps.task_id))) and ((task_steps.owner_id = (select target.owner_id from public.tasks target where target.id = task_steps.task_id))));
revoke all on public.task_steps from anon;
revoke all on public.task_steps from authenticated;
grant select on public.task_steps to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_steps') then
    alter publication supabase_realtime add table public.task_steps;
  end if;
end;
$$;


create or replace function public.capture_task_steps_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.local_entity_changes where entity_type = 'TaskStep' and entity_id = new.id and audience_user_id is null;
  insert into public.local_entity_changes (entity_type, entity_id, owner_id, server_version, operation_id, audience_user_id, is_revocation, record)
  values ('TaskStep', new.id, new.owner_id, new.server_version, nullif(current_setting('app.operation_id', true), '')::uuid, null, false, to_jsonb(new));
  return new;
end;
$$;
revoke all on function public.capture_task_steps_change() from public, anon, authenticated, service_role;
drop trigger if exists task_steps_capture_change on public.task_steps;
create trigger task_steps_capture_change after insert or update on public.task_steps for each row execute function public.capture_task_steps_change();

create or replace function public.upcast_task_steps_operation(p_operation jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  current_version integer;
begin
  current_version := coalesce((p_operation ->> 'protocolVersion')::integer, 0);
  if current_version < 1 or current_version > 2 then
    raise exception 'Unsupported protocol version' using errcode = '22023';
  end if;
  if jsonb_typeof(p_operation -> 'patch') <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;
  if current_version < 2 then
    if p_operation ->> 'operation' = 'create' and not ((p_operation -> 'patch') ? 'orderRank') then
      p_operation := jsonb_set(p_operation, '{patch,orderRank}', '"057896044618658097711785492504343953926634992332820282019728792003956564819967"'::jsonb, true);
    end if;
    p_operation := jsonb_set(p_operation, '{protocolVersion}', '2'::jsonb, true);
    current_version := 2;
  end if;
  return p_operation;
end;
$$;

create or replace function public.apply_task_steps_patch(
  p_id uuid,
  p_base_server_version bigint,
  p_operation text,
  p_patch jsonb
) returns public.task_steps
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_row public.task_steps;
  updated_row public.task_steps;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_operation not in ('patch', 'delete') then
    raise exception 'Unsupported operation' using errcode = '22023';
  end if;
  if p_operation = 'patch' and not (public.is_task_steps_owner(p_id) or public.is_task_steps_reference(p_id)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  if p_operation = 'delete' and not (public.is_task_steps_owner(p_id) or public.is_task_steps_reference(p_id)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  if p_operation = 'patch' and exists (
    select 1 from jsonb_object_keys(p_patch) key where not (key = any(array['done']::text[]))
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
  if (p_patch) ? 'taskId' and jsonb_typeof(p_patch -> 'taskId') <> 'null' and not (public.is_tasks_owner((p_patch ->> 'taskId')::uuid) or public.is_tasks_collaborator((p_patch ->> 'taskId')::uuid)) then
    raise exception 'Referenced entity access denied' using errcode = '42501';
  end if;
  select * into current_row from public.task_steps where id = p_id for update;
  if not found then
    raise exception 'Entity not found' using errcode = 'P0002';
  end if;
  if current_row.server_version <> p_base_server_version then
    raise exception 'Version conflict' using errcode = 'PT409';
  end if;
  if p_operation = 'patch' and p_patch ? 'done'
     and not ((p_patch ?& array['done']::text[] and ((p_patch -> 'done' #>> '{}')::boolean) is not distinct from true) or (p_patch ?& array['done']::text[] and ((p_patch -> 'done' #>> '{}')::boolean) is not distinct from false)) then
    raise exception 'Patch does not match a declared entity action' using errcode = '22023';
  end if;
  update public.task_steps
  set
    done = case when p_operation = 'patch' and p_patch ? 'done' then (p_patch -> 'done' #>> '{}')::boolean else current_row.done end,
    deleted_at = case when p_operation = 'delete' and p_patch ? 'deletedAt' then (p_patch -> 'deletedAt' #>> '{}')::timestamptz else current_row.deleted_at end
    , server_version = current_row.server_version + 1
  where id = p_id
  returning * into updated_row;
  return updated_row;
end;
$$;

create or replace function public.push_task_steps_operations(p_operations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_operation jsonb;
  operation_uuid uuid;
  receipt_result jsonb;
  canonical public.task_steps;
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
  related_changes jsonb;
  converged boolean;
  change_sequence bigint;
  results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_writable('TaskStep') then
    raise exception 'Agents cannot change this entity' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_session_active() then
    raise exception 'Agent access was revoked' using errcode = '42501';
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
    converged := false;
    current_operation := public.upcast_task_steps_operation(current_operation);
    operation_uuid := (current_operation ->> 'operationId')::uuid;
    if current_operation ->> 'entityType' <> 'TaskStep' then
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
          where not (key = any(array['id', 'ownerId', 'taskId', 'title', 'done', 'orderRank']::text[])))
          or not ((current_operation -> 'patch') ?& array['id', 'ownerId', 'taskId', 'title', 'done'])
          or (not (current_operation ? 'orderedCreate') and not ((current_operation -> 'patch') ? 'orderRank')) then
        raise exception 'Create contains missing or forbidden fields' using errcode = '22023';
      end if;
      if (current_operation -> 'patch' ->> 'id')::uuid
          <> (current_operation ->> 'entityId')::uuid then
        raise exception 'Create entity ID mismatch' using errcode = '22023';
      end if;
      if not (((current_operation -> 'patch' ->> 'ownerId')::uuid = auth.uid() or (public.is_tasks_owner((current_operation -> 'patch' ->> 'taskId')::uuid) or public.is_tasks_collaborator((current_operation -> 'patch' ->> 'taskId')::uuid))) and (((current_operation -> 'patch' ->> 'ownerId')::uuid = (select target.owner_id from public.tasks target where target.id = (current_operation -> 'patch' ->> 'taskId')::uuid)))) then
        raise exception 'Create access denied' using errcode = '42501';
      end if;

      if ((current_operation -> 'patch' -> 'done' #>> '{}')::boolean) is distinct from false then
        raise exception 'Invalid initial entity action state' using errcode = '23514';
      end if;
      if (current_operation -> 'patch') ? 'taskId' and jsonb_typeof(current_operation -> 'patch' -> 'taskId') <> 'null' and not (public.is_tasks_owner((current_operation -> 'patch' ->> 'taskId')::uuid) or public.is_tasks_collaborator((current_operation -> 'patch' ->> 'taskId')::uuid)) then
        raise exception 'Referenced entity access denied' using errcode = '42501';
      end if;
      if uuid_extract_version((current_operation ->> 'entityId')::uuid) = 5
          and (current_operation ->> 'entityId')::uuid is distinct from public.task_steps_id_for((current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid, current_operation -> 'patch' -> 'title' #>> '{}') then
        raise exception 'Create identity does not derive from its key' using errcode = '22023';
      end if;
      perform pg_advisory_xact_lock(
        hashtextextended('TaskStep:' || (current_operation ->> 'entityId'), 0)
      );
      select * into canonical from public.task_steps
      where id = (current_operation ->> 'entityId')::uuid;
      converged := found;
      if converged and not (canonical.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid)
          and canonical.task_id is not distinct from ((current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid)
          and canonical.title is not distinct from (current_operation -> 'patch' -> 'title' #>> '{}')) then
        raise exception 'Create identity is taken' using errcode = '23505';
      end if;
      if not converged then
        order_scope_key := jsonb_build_array(current_operation -> 'patch' -> 'ownerId', current_operation -> 'patch' -> 'taskId')::text;
        perform pg_advisory_xact_lock(
          hashtextextended('TaskStep:' || order_scope_key, 0)
        );
        insert into public.local_entity_order_scopes (entity_type, scope_key)
        values ('TaskStep', order_scope_key)
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
          where scope.entity_type = 'TaskStep'
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
            from public.task_steps member
            where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.task_id is not distinct from ((current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid)
            order by member.order_rank, member.id
            limit 1;
            if not found then
              upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
            end if;
          else
            upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
            select member.order_rank::numeric into lower_order_rank
            from public.task_steps member
            where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.task_id is not distinct from ((current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid)
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
                  from public.task_steps member
                  where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.task_id is not distinct from ((current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid)
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
                  from public.task_steps member
                  where member.deleted_at is null and member.owner_id is not distinct from ((current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid) and member.task_id is not distinct from ((current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid)
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
                update public.task_steps member
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
        insert into public.task_steps (id, owner_id, task_id, title, done, order_rank)
        values ((current_operation -> 'patch' -> 'id' #>> '{}')::uuid, (current_operation -> 'patch' -> 'ownerId' #>> '{}')::uuid, (current_operation -> 'patch' -> 'taskId' #>> '{}')::uuid, current_operation -> 'patch' -> 'title' #>> '{}', (current_operation -> 'patch' -> 'done' #>> '{}')::boolean, current_operation -> 'patch' -> 'orderRank' #>> '{}') returning * into canonical;
        update public.local_entity_order_scopes
        set version = version + 1
        where entity_type = 'TaskStep' and scope_key = order_scope_key
        returning version into current_order_scope_version;
      end if;
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
  if not (public.is_task_steps_owner((current_operation ->> 'entityId')::uuid) or public.is_task_steps_reference((current_operation ->> 'entityId')::uuid)) then
    raise exception 'Entity access denied' using errcode = '42501';
  end if;
  select jsonb_build_array(owner_id, task_id)::text into order_scope_key
  from public.task_steps
  where id = (current_operation ->> 'entityId')::uuid
    and deleted_at is null;
  if not found then
    raise exception 'Ordered entity not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('TaskStep:' || order_scope_key, 0)
  );
  select candidate.* into canonical from public.task_steps candidate
  where candidate.id = (current_operation ->> 'entityId')::uuid
    and candidate.deleted_at is null
    and jsonb_build_array(candidate.owner_id, candidate.task_id)::text = order_scope_key
  for update;
  if not found then
    raise exception 'Ordered entity left its canonical scope' using errcode = 'PT409';
  end if;
  insert into public.local_entity_order_scopes (entity_type, scope_key)
  values ('TaskStep', order_scope_key)
  on conflict (entity_type, scope_key) do nothing;
  select scope.version into current_order_scope_version
  from public.local_entity_order_scopes scope
  where scope.entity_type = 'TaskStep'
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
    from public.task_steps neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.task_id is not distinct from canonical.task_id
    order by neighbor.order_rank, neighbor.id
    limit 1;
    if not found then
      upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    end if;
  elsif current_operation -> 'patch' ->> 'placement' = 'last' then
    upper_order_rank := 115792089237316195423570985008687907853269984665640564039457584007913129639935::numeric;
    select neighbor.order_rank::numeric into lower_order_rank
    from public.task_steps neighbor
    where neighbor.deleted_at is null
      and neighbor.id <>
          (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.task_id is not distinct from canonical.task_id
    order by neighbor.order_rank desc,
             neighbor.id desc
    limit 1;
    if not found then
      lower_order_rank := 0;
    end if;
  else
    select neighbor.order_rank::numeric into anchor_order_rank
    from public.task_steps neighbor
    where neighbor.id =
        (current_operation -> 'patch' ->> 'anchorId')::uuid
      and neighbor.deleted_at is null and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.task_id is not distinct from canonical.task_id;
    if not found then
      raise exception 'Ordered anchor is outside the canonical scope'
        using errcode = '22023';
    end if;
    if current_operation -> 'patch' ->> 'placement' = 'before' then
      upper_order_rank := anchor_order_rank;
      select neighbor.order_rank::numeric into lower_order_rank
      from public.task_steps neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.task_id is not distinct from canonical.task_id
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
      from public.task_steps neighbor
      where neighbor.deleted_at is null
        and neighbor.id <>
            (current_operation ->> 'entityId')::uuid and neighbor.owner_id is not distinct from canonical.owner_id and neighbor.task_id is not distinct from canonical.task_id
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
        from public.task_steps member
        where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id and member.task_id is not distinct from canonical.task_id      and member.id <>
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
        from public.task_steps member
        where member.deleted_at is null and member.owner_id is not distinct from canonical.owner_id and member.task_id is not distinct from canonical.task_id      and member.id <>
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
      update public.task_steps member
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
  update public.task_steps
  set order_rank = lpad(next_order_rank::text, 78, '0'),
      server_version =
        server_version + 1
  where id = canonical.id
  returning * into canonical;
  update public.local_entity_order_scopes scope
  set version = scope.version + 1
  where scope.entity_type = 'TaskStep'
    and scope.scope_key = order_scope_key
  returning scope.version into current_order_scope_version;
      else
        raise exception 'Unsupported command' using errcode = '22023';
      end if;
    elsif current_operation ->> 'operation' in ('patch', 'delete') then
      if current_operation -> 'patch' ?| array['deletedAt'] then
        if current_operation ->> 'operation' = 'delete'
           and not (public.is_task_steps_owner((current_operation ->> 'entityId')::uuid) or public.is_task_steps_reference((current_operation ->> 'entityId')::uuid)) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        if current_operation ->> 'operation' = 'patch'
           and not (public.is_task_steps_owner((current_operation ->> 'entityId')::uuid) or public.is_task_steps_reference((current_operation ->> 'entityId')::uuid)) then
          raise exception 'Entity access denied' using errcode = '42501';
        end if;
        select jsonb_build_array(candidate.owner_id, candidate.task_id)::text,
               (candidate.deleted_at is null) <>
                 (case
      when current_operation -> 'patch' ? 'deletedAt' then
        current_operation -> 'patch' -> 'deletedAt' = 'null'::jsonb
      else candidate.deleted_at is null
    end)
        into order_scope_key, order_scope_membership_changed
        from public.task_steps candidate
        where candidate.id =
          (current_operation ->> 'entityId')::uuid;
        if not found then
          raise exception 'Entity not found' using errcode = 'P0002';
        end if;
        if order_scope_membership_changed then
          perform pg_advisory_xact_lock(
            hashtextextended('TaskStep:' || order_scope_key, 0)
          );
          insert into public.local_entity_order_scopes (entity_type, scope_key)
          values ('TaskStep', order_scope_key)
          on conflict (entity_type, scope_key) do nothing;
          select scope.version into current_order_scope_version
          from public.local_entity_order_scopes scope
          where scope.entity_type = 'TaskStep'
            and scope.scope_key = order_scope_key
          for update;
        end if;
      end if;
      canonical := public.apply_task_steps_patch(
        (current_operation ->> 'entityId')::uuid,
        (current_operation ->> 'baseServerVersion')::bigint,
        current_operation ->> 'operation',
        current_operation -> 'patch');
      if order_scope_membership_changed then
        update public.local_entity_order_scopes
        set version = version + 1
        where entity_type = 'TaskStep' and scope_key = order_scope_key
        returning version into current_order_scope_version;
      end if;
    end if;
    if converged then
      select changes.sequence into change_sequence from public.local_entity_changes changes where changes.entity_type = 'TaskStep' and changes.entity_id = canonical.id and (changes.audience_user_id is null or changes.audience_user_id = auth.uid()) order by changes.sequence desc limit 1;
    else
      select changes.sequence into change_sequence from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() and changes.entity_type = 'TaskStep' and changes.entity_id = canonical.id order by changes.sequence desc limit 1;
    end if;
    if change_sequence is null then
      raise exception 'Accepted operation has no change-log entry' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('entityType', changes.entity_type, 'record', changes.record, 'sequence', changes.sequence, 'operationId', changes.operation_id, 'serverVersion', changes.server_version) order by changes.sequence), '[]'::jsonb) into related_changes from public.local_entity_changes changes where changes.operation_id = operation_uuid and changes.written_by = auth.uid() and changes.audience_user_id is null and not changes.is_revocation and not (changes.entity_type = 'TaskStep' and changes.entity_id = canonical.id);
    if current_order_scope_version is not null then
      order_scope_versions := jsonb_build_array(
        jsonb_build_object('scope', jsonb_build_object('ownerId', canonical.owner_id, 'taskId', canonical.task_id), 'version', current_order_scope_version)
      );
    end if;
    receipt_result := jsonb_build_object('record', to_jsonb(canonical), 'sequence', change_sequence, 'operationId', operation_uuid, 'serverVersion', canonical.server_version, 'scopeVersions', order_scope_versions, 'relatedChanges', related_changes);
    if converged then
      receipt_result := receipt_result || jsonb_build_object('converged', true);
    end if;
    insert into public.local_entity_operation_receipts (operation_id, user_id, entity_type, entity_id, result) values (operation_uuid, auth.uid(), 'TaskStep', canonical.id, receipt_result);
    results := results || jsonb_build_array(receipt_result);
  end loop;
  return results;
end;
$$;

revoke all on function public.upcast_task_steps_operation(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.apply_task_steps_patch(uuid, bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.push_task_steps_operations(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.push_task_steps_operations(jsonb) to authenticated;

-- Reference-derived access propagation for Task.

create or replace function public.publish_tasks_reference_access(
  p_target_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.local_entity_changes changes
  using public.task_steps entity
  where changes.entity_type = 'TaskStep'
    and changes.entity_id = entity.id
    and changes.audience_user_id = p_user_id
    and (entity.task_id = p_target_id);
  insert into public.local_entity_changes (
    entity_type, entity_id, owner_id, server_version,
    operation_id, audience_user_id, is_revocation, record
  )
  select
    'TaskStep',
    entity.id,
    entity.owner_id,
    entity.server_version,
    nullif(current_setting('app.operation_id', true), '')::uuid,
    p_user_id,
    not dependent_access.readable,
    case when dependent_access.readable then to_jsonb(entity) else jsonb_build_object('id', entity.id) end
  from public.task_steps entity
  cross join lateral (select (entity.owner_id = p_user_id or (exists (select 1 from public.tasks access_task_id where access_task_id.id = entity.task_id and (access_task_id.owner_id = p_user_id or exists (select 1 from public.task_members member where member.task_id = access_task_id.id and member.user_id = p_user_id and member.active)))) and ((entity.owner_id = (select ownership_target.owner_id from public.tasks ownership_target where ownership_target.id = entity.task_id)))) as readable) dependent_access
  where entity.task_id = p_target_id;
  return;
end;
$$;

revoke all on function public.publish_tasks_reference_access(uuid, uuid) from public, anon, authenticated, service_role;
create or replace function public.publish_task_members_reference_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
  user_id uuid;
  was_active boolean := false;
  is_active boolean := false;
begin
  if tg_op <> 'INSERT' then
    was_active := old.active;
  end if;
  if tg_op <> 'DELETE' then
    is_active := new.active;
  end if;
  if was_active = is_active then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  target_id := case when tg_op = 'DELETE'
    then old.task_id
    else new.task_id end;
  user_id := case when tg_op = 'DELETE'
    then old.user_id
    else new.user_id end;
  perform public.publish_tasks_reference_access(target_id, user_id);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

revoke all on function public.publish_task_members_reference_access() from public, anon, authenticated, service_role;
drop trigger if exists task_members_publish_reference_access
on public.task_members;
create trigger task_members_publish_reference_access
after insert or update of active or delete
on public.task_members
for each row execute function public.publish_task_members_reference_access();

-- Who may pull each change, decided once when it is recorded. Access granted
-- later arrives as its own addressed snapshot, so a change's recipients are
-- exactly the accounts that may read the entity at that moment.

create or replace function public.tasks_example_change_recipients(
  p_entity_type text,
  p_entity_id uuid,
  p_owner_id uuid
) returns table (user_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case p_entity_type
    when 'Task' then
      return query
      select distinct candidate.user_id
      from (select p_owner_id as user_id
        union select recipient_tasks_tasks.owner_id as user_id from public.tasks recipient_tasks_tasks where recipient_tasks_tasks.id = p_entity_id
        union select recipient_tasks_member.user_id as user_id from public.task_members recipient_tasks_member where recipient_tasks_member.task_id = p_entity_id and recipient_tasks_member.active) candidate
      where candidate.user_id = p_owner_id
        or exists (
          select 1 from public.tasks target_row
          where target_row.id = p_entity_id
            and (target_row.owner_id = candidate.user_id or exists (select 1 from public.task_members member where member.task_id = target_row.id and member.user_id = candidate.user_id and member.active))
        );
    when 'TaskActivity' then
      return query
      select distinct candidate.user_id
      from (select p_owner_id as user_id
        union select recipient_task_activities_tasks.owner_id as user_id from public.tasks recipient_task_activities_tasks where recipient_task_activities_tasks.id = (select activity.subject_id from public.task_activities activity where activity.id = p_entity_id)
        union select recipient_task_activities_member.user_id as user_id from public.task_members recipient_task_activities_member where recipient_task_activities_member.task_id = (select activity.subject_id from public.task_activities activity where activity.id = p_entity_id) and recipient_task_activities_member.active) candidate
      where candidate.user_id = p_owner_id
        or exists (
          select 1 from public.tasks target_row
          where target_row.id = (select activity.subject_id from public.task_activities activity where activity.id = p_entity_id)
            and (target_row.owner_id = candidate.user_id or exists (select 1 from public.task_members member where member.task_id = target_row.id and member.user_id = candidate.user_id and member.active))
        );
    when 'TaskProject' then
      return query select p_owner_id;
    when 'TaskStep' then
      return query
      select distinct candidate.user_id
      from (select p_owner_id as user_id
        union select recipient_task_steps_task_steps.owner_id as user_id from public.task_steps recipient_task_steps_task_steps where recipient_task_steps_task_steps.id = p_entity_id
        union select recipient_task_steps_reference_1_tasks.owner_id as user_id from public.tasks recipient_task_steps_reference_1_tasks where recipient_task_steps_reference_1_tasks.id = (select recipient_task_steps_reference_1.task_id from public.task_steps recipient_task_steps_reference_1 where recipient_task_steps_reference_1.id = p_entity_id)
        union select recipient_task_steps_reference_1_member.user_id as user_id from public.task_members recipient_task_steps_reference_1_member where recipient_task_steps_reference_1_member.task_id = (select recipient_task_steps_reference_1.task_id from public.task_steps recipient_task_steps_reference_1 where recipient_task_steps_reference_1.id = p_entity_id) and recipient_task_steps_reference_1_member.active) candidate
      where candidate.user_id = p_owner_id
        or exists (
          select 1 from public.task_steps target_row
          where target_row.id = p_entity_id
            and (target_row.owner_id = candidate.user_id or (exists (select 1 from public.tasks access_task_id where access_task_id.id = target_row.task_id and (access_task_id.owner_id = candidate.user_id or exists (select 1 from public.task_members member where member.task_id = access_task_id.id and member.user_id = candidate.user_id and member.active)))) and ((target_row.owner_id = (select ownership_target.owner_id from public.tasks ownership_target where ownership_target.id = target_row.task_id))))
        );
    else
      return;
  end case;
end;
$$;

revoke all on function public.tasks_example_change_recipients(text, uuid, uuid) from public, anon, authenticated, service_role;

create or replace function public.address_tasks_example_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
    from public.tasks_example_change_recipients(
      new.entity_type,
      new.entity_id,
      new.owner_id
    ) recipient
    join auth.users account on account.id = recipient.user_id
    on conflict do nothing;
  end if;
  return null;
end;
$$;

revoke all on function public.address_tasks_example_change() from public, anon, authenticated, service_role;
drop trigger if exists local_entity_changes_address_tasks_example on public.local_entity_changes;
create trigger local_entity_changes_address_tasks_example
after insert on public.local_entity_changes
for each row execute function public.address_tasks_example_change();

-- One globally ordered pull contract for this synchronization target. It reads
-- only the changes addressed to the caller, by index, in sequence order. A page
-- is full when 500 sequences are addressed, however many of them still hold a
-- change, so a short page always means the caller has caught up.

create or replace function public.pull_tasks_example_graph_changes(p_after_sequence bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  page jsonb := '[]'::jsonb;
  addressed_sequences bigint[];
  page_full boolean;
  next_cursor bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.is_agent_request() then
    raise exception 'Agents read through run_agent_tool' using errcode = '42501';
  end if;
  select coalesce(array_agg(addressed.sequence order by addressed.sequence), '{}')
  into addressed_sequences
  from (
    select recipient.sequence from public.local_entity_change_recipients recipient where recipient.user_id = auth.uid() and recipient.sequence > p_after_sequence
    order by 1
    limit 500
  ) addressed;
  page_full := cardinality(addressed_sequences) = 500;
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
    where changes.sequence = any(addressed_sequences)
  ) visible;
  if page_full then
    next_cursor := addressed_sequences[500];
  else
    select coalesce(max(changes.sequence), p_after_sequence)
      into next_cursor
    from public.local_entity_changes changes;
  end if;
  return jsonb_build_object(
    'changes', page,
    'nextSequence', next_cursor,
    'hasMore', page_full
  );
end;
$$;

revoke all on function public.pull_tasks_example_graph_changes(bigint) from public, anon, authenticated, service_role;
grant execute on function public.pull_tasks_example_graph_changes(bigint) to authenticated;

-- Ownership succession and audience-safe retirement before a principal's
-- identity is removed. Callers delete the identity in the same transaction.

create or replace function public.retire_tasks_example_graph_principal(p_principal uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

  -- Task passes to its longest-standing active collaborator,
  -- preferring one who may edit.
  for handover in
    select root.id as entity_id, (
      select member.user_id from public.task_members member
      where member.task_id = root.id
        and member.active
        and member.user_id <> p_principal
      order by member.user_id
      limit 1
    ) as successor_id
    from public.tasks root
    where root.owner_id = p_principal
      and root.deleted_at is null
  loop
    continue when handover.successor_id is null;
    delete from public.task_members
    where task_id = handover.entity_id
      and user_id = handover.successor_id;
    update public.tasks
    set owner_id = handover.successor_id,
      server_version = server_version + 1
    where id = handover.entity_id;
    insert into pg_temp.nodus_principal_successions (entity_type, entity_id)
    values ('Task', handover.entity_id)
    on conflict do nothing;
  end loop;

  -- Rows derived from a successor-owned row follow it until nothing moves.
  loop
    repaired := 0;
    -- TaskStep follows its owner reference taskId.
    with moved as (
      update public.task_steps dependent
      set owner_id = target.owner_id,
        server_version = dependent.server_version + 1
      from public.tasks target
      where target.id = dependent.task_id
        and dependent.owner_id = p_principal
        and target.owner_id <> p_principal
      returning dependent.id as id
    )
    insert into pg_temp.nodus_principal_successions (entity_type, entity_id)
    select 'TaskStep', moved.id from moved
    on conflict do nothing;
    get diagnostics moved_count = row_count;
    repaired := repaired + moved_count;
    exit when repaired = 0;
  end loop;

  -- Retire the principal's direct Task memberships.
  delete from public.task_members
  where user_id = p_principal;

  -- Task.projectId detaches from a retired TaskProject.
  update public.tasks dependent
  set project_id = null, server_version = dependent.server_version + 1
  where dependent.owner_id <> p_principal
    and dependent.project_id in (
      select target.id from public.task_projects target
      where target.owner_id = p_principal
    );

  -- A successor last sees its inherited rows as their owner, after any
  -- revocation its own retired membership published.
  update public.tasks successor
  set server_version = successor.server_version + 1
  where successor.id in (
    select succession.entity_id from pg_temp.nodus_principal_successions succession
    where succession.entity_type = 'Task'
  );
  update public.task_activities successor
  set server_version = successor.server_version + 1
  where successor.id in (
    select succession.entity_id from pg_temp.nodus_principal_successions succession
    where succession.entity_type = 'TaskActivity'
  );
  update public.task_projects successor
  set server_version = successor.server_version + 1
  where successor.id in (
    select succession.entity_id from pg_temp.nodus_principal_successions succession
    where succession.entity_type = 'TaskProject'
  );
  update public.task_steps successor
  set server_version = successor.server_version + 1
  where successor.id in (
    select succession.entity_id from pg_temp.nodus_principal_successions succession
    where succession.entity_type = 'TaskStep'
  );



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
$$;

revoke all on function public.retire_tasks_example_graph_principal(uuid) from public, anon, authenticated, service_role;

-- Derived identities and member operations declared in Nodus.

create or replace function public.nodus_uuid_v5(p_namespace uuid, p_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  hash bytea := substring(
    extensions.digest(
      decode(replace(p_namespace::text, '-', ''), 'hex') ||
        convert_to(p_name, 'UTF8'),
      'sha1'
    ) from 1 for 16
  );
begin
  hash := set_byte(hash, 6, (get_byte(hash, 6) & 15) | 80);
  hash := set_byte(hash, 8, (get_byte(hash, 8) & 63) | 128);
  return encode(hash, 'hex')::uuid;
end;
$$;

create or replace function public.task_steps_id_for(p_task_id uuid, p_title text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select public.nodus_uuid_v5('6f1d2c3b-8a4e-4b7f-9c0d-2e5a7b9c1d3f'::uuid, p_task_id::text || '/' || p_title::text)
$$;

create or replace function public.tasks_add_step(
  p_root_id uuid,
  p_arguments jsonb
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  member public.task_steps;
  removed public.task_steps;
  anchor public.task_steps;
  after_row public.task_steps;
  before_row public.task_steps;
  in_group boolean;
  key_title text := nullif(p_arguments -> 'title' ->> 'title', '')::text;


begin
  if public.is_agent_request() then
    raise exception 'Agents cannot run this operation' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.tasks root_row where root_row.id = p_root_id
  ) then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;
  if num_nonnulls(key_title) <> 1 then
    raise exception 'Name the task step with exactly one of title'
      using errcode = '22023';
  end if;
  select * into member from public.task_steps item
    where item.task_id = p_root_id and item.title is not distinct from key_title and item.deleted_at is null
    order by item.order_rank, item.id limit 1;
  if (member.id is not null) then
    return;
  end if;
  if member.id is null then
    select * into removed from public.task_steps item
      where item.task_id = p_root_id and item.title is not distinct from key_title and item.deleted_at is not null
      order by item.order_rank, item.id limit 1;
    if removed.id is null then
      perform public.push_task_steps_operations(jsonb_build_array(jsonb_build_object(
        'operationId', gen_random_uuid(),
        'operation', 'create',
        'entityType', 'TaskStep',
        'entityId', public.task_steps_id_for(p_root_id, key_title),
        'baseServerVersion', 0,
        'protocolVersion', 2,
        'orderedCreate', jsonb_build_object('placement', 'last', 'scopeBaseVersion', 0),
        'patch', jsonb_build_object('id', to_jsonb(public.task_steps_id_for(p_root_id, key_title)), 'ownerId', to_jsonb((select root_row.owner_id from public.tasks root_row where root_row.id = p_root_id)), 'taskId', to_jsonb(p_root_id), 'title', to_jsonb(key_title), 'done', 'false'::jsonb)
      )));
    else
      perform public.push_task_steps_operations(jsonb_build_array(jsonb_build_object(
        'operationId', gen_random_uuid(),
        'operation', 'delete',
        'entityType', 'TaskStep',
        'entityId', removed.id,
        'baseServerVersion', removed.server_version,
        'protocolVersion', 2,
        'patch', jsonb_build_object('deletedAt', 'null'::jsonb)
      )));
      select * into removed from public.task_steps item where item.id = removed.id;
      perform public.push_task_steps_operations(jsonb_build_array(jsonb_build_object(
        'operationId', gen_random_uuid(),
        'operation', 'patch',
        'entityType', 'TaskStep',
        'entityId', removed.id,
        'baseServerVersion', removed.server_version,
        'protocolVersion', 2,
        'patch', jsonb_build_object('done', 'false'::jsonb)
      )));
      select * into removed from public.task_steps item where item.id = removed.id;
      perform public.push_task_steps_operations(jsonb_build_array(jsonb_build_object(
        'operationId', gen_random_uuid(),
        'operation', 'command',
        'entityType', 'TaskStep',
        'entityId', removed.id,
        'baseServerVersion', removed.server_version,
        'protocolVersion', 2,
        'commandName', 'moveInOrder',
        'patch', jsonb_build_object('placement', 'last', 'anchorId', 'null'::jsonb, 'scopeBaseVersion', 0)
      )));
      select * into removed from public.task_steps item where item.id = removed.id;
    end if;
    select * into member from public.task_steps item
    where item.task_id = p_root_id and item.title is not distinct from key_title and item.deleted_at is null
    order by item.order_rank, item.id limit 1;
  end if;
end;
$$;

create or replace function public.tasks_check_step(
  p_root_id uuid,
  p_arguments jsonb
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  member public.task_steps;
  removed public.task_steps;
  anchor public.task_steps;
  after_row public.task_steps;
  before_row public.task_steps;
  in_group boolean;
  key_title text := nullif(p_arguments -> 'title' ->> 'title', '')::text;


begin
  if public.is_agent_request() then
    raise exception 'Agents cannot run this operation' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.tasks root_row where root_row.id = p_root_id
  ) then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;
  if num_nonnulls(key_title) <> 1 then
    raise exception 'Name the task step with exactly one of title'
      using errcode = '22023';
  end if;
  select * into member from public.task_steps item
    where item.task_id = p_root_id and item.title is not distinct from key_title and item.deleted_at is null
    order by item.order_rank, item.id limit 1;
  if not (member.id is not null) then
    raise exception 'The task has no such step.' using errcode = '22023';
  end if;
  perform public.push_task_steps_operations(jsonb_build_array(jsonb_build_object(
    'operationId', gen_random_uuid(),
    'operation', 'patch',
    'entityType', 'TaskStep',
    'entityId', member.id,
    'baseServerVersion', member.server_version,
    'protocolVersion', 2,
    'patch', jsonb_build_object('done', 'true'::jsonb)
  )));
  select * into member from public.task_steps item where item.id = member.id;
end;
$$;

revoke all on function public.nodus_uuid_v5(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.nodus_uuid_v5(uuid, text) to authenticated;
revoke all on function public.task_steps_id_for(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.task_steps_id_for(uuid, text) to authenticated;
revoke all on function public.tasks_add_step(uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.tasks_add_step(uuid, jsonb) to authenticated;
revoke all on function public.tasks_check_step(uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.tasks_check_step(uuid, jsonb) to authenticated;





-- Agent tool surface: what AI agents signed in through OAuth
-- may read and change, derived from AgentAccess declarations.

create or replace function public.is_agent_request()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ? 'client_id', false)
$$;

create or replace function public.agent_session_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.sessions session
    where session.id = nullif(auth.jwt() ->> 'session_id', '')::uuid
  )
$$;

create or replace function public.agent_writable(p_entity_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_entity_type = any(array[]::text[])
$$;

create or replace function public.agent_require_access()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.is_agent_request() and not public.agent_session_active() then
    raise exception 'Agent access was revoked' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.agent_uuid(p_key text, p_part text)
returns uuid
language sql
volatile
set search_path = ''
as $$
  select case
    when p_key is null then gen_random_uuid()
    else md5(auth.uid()::text || ':' || p_key || ':' || p_part)::uuid
  end
$$;

create or replace function public.agent_now()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

create or replace function public.agent_check_arguments(
  p_arguments jsonb,
  p_allowed text[]
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
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
$$;

create or replace function public.agent_required(
  p_arguments jsonb,
  p_name text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
begin
  if not (p_arguments ? p_name) or jsonb_typeof(p_arguments -> p_name) = 'null' then
    raise exception 'Missing argument "%"', p_name using errcode = '22023';
  end if;
  return p_arguments -> p_name;
end;
$$;

create or replace function public.agent_flags_in(
  p_value jsonb,
  p_names text[]
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
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
$$;

create or replace function public.agent_flags_out(
  p_value bigint,
  p_names text[]
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_value is null then 'null'::jsonb else coalesce((
    select jsonb_agg(flag.name order by flag.position)
    from unnest(p_names) with ordinality as flag(name, position)
    where p_value & (1::bigint << (flag.position::integer - 1)) <> 0
  ), '[]'::jsonb) end
$$;

revoke all on function public.agent_session_active() from public, anon, authenticated, service_role;
grant execute on function public.agent_session_active() to authenticated;

create or replace function public.list_agent_tools()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select $agent_tools$[]$agent_tools$::jsonb
$$;

revoke all on function public.list_agent_tools() from public, anon, authenticated, service_role;
grant execute on function public.list_agent_tools() to authenticated;

create or replace function public.run_agent_tool(
  p_tool text,
  p_arguments jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  arguments jsonb := coalesce(p_arguments, '{}'::jsonb);
begin
  perform public.agent_require_access();
  case p_tool

    else raise exception 'Unknown agent tool "%"', p_tool using errcode = '22023';
  end case;
end;
$$;

revoke all on function public.run_agent_tool(text, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.run_agent_tool(text, jsonb) to authenticated;

revoke all on function public.is_agent_request() from public, anon, authenticated, service_role;
grant execute on function public.is_agent_request() to authenticated;
revoke all on function public.agent_writable(text) from public, anon, authenticated, service_role;
grant execute on function public.agent_writable(text) to authenticated;
revoke all on function public.agent_require_access() from public, anon, authenticated, service_role;
grant execute on function public.agent_require_access() to authenticated;
revoke all on function public.agent_uuid(text, text) from public, anon, authenticated, service_role;
grant execute on function public.agent_uuid(text, text) to authenticated;
revoke all on function public.agent_now() from public, anon, authenticated, service_role;
grant execute on function public.agent_now() to authenticated;
revoke all on function public.agent_check_arguments(jsonb, text[]) from public, anon, authenticated, service_role;
grant execute on function public.agent_check_arguments(jsonb, text[]) to authenticated;
revoke all on function public.agent_required(jsonb, text) from public, anon, authenticated, service_role;
grant execute on function public.agent_required(jsonb, text) to authenticated;
revoke all on function public.agent_flags_in(jsonb, text[]) from public, anon, authenticated, service_role;
grant execute on function public.agent_flags_in(jsonb, text[]) to authenticated;
revoke all on function public.agent_flags_out(bigint, text[]) from public, anon, authenticated, service_role;
grant execute on function public.agent_flags_out(bigint, text[]) to authenticated;
create policy "tasks_agent_scope"
on public.tasks
as restrictive
for all
to authenticated
using (not public.is_agent_request())
with check (not public.is_agent_request());

create policy "task_activities_agent_scope"
on public.task_activities
as restrictive
for all
to authenticated
using (not public.is_agent_request())
with check (not public.is_agent_request());

create policy "task_projects_agent_scope"
on public.task_projects
as restrictive
for all
to authenticated
using (not public.is_agent_request())
with check (not public.is_agent_request());

create policy "task_steps_agent_scope"
on public.task_steps
as restrictive
for all
to authenticated
using (not public.is_agent_request())
with check (not public.is_agent_request());

create policy "local_entity_changes_agent_scope"
on public.local_entity_changes
as restrictive
for select
to authenticated
using (not (select public.is_agent_request()));
