set check_function_bodies = off;

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
    raise exception 'Version conflict' using errcode = '40001';
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


