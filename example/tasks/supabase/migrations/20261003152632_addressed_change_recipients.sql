
  create table "public"."local_entity_change_recipients" (
    "user_id" uuid not null,
    "sequence" bigint not null
      );


alter table "public"."local_entity_change_recipients" enable row level security;

CREATE UNIQUE INDEX local_entity_change_recipients_pkey ON public.local_entity_change_recipients USING btree (user_id, sequence);

alter table "public"."local_entity_change_recipients" add constraint "local_entity_change_recipients_pkey" PRIMARY KEY using index "local_entity_change_recipients_pkey";

alter table "public"."local_entity_change_recipients" add constraint "local_entity_change_recipients_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."local_entity_change_recipients" validate constraint "local_entity_change_recipients_user_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.address_tasks_example_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.tasks_example_change_recipients(p_entity_type text, p_entity_id uuid, p_owner_id uuid)
 RETURNS TABLE(user_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    else
      return;
  end case;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.pull_tasks_example_graph_changes(p_after_sequence bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      select recipient.sequence from public.local_entity_change_recipients recipient where recipient.user_id = auth.uid() and recipient.sequence > p_after_sequence
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
$function$
;

grant references on table "public"."local_entity_change_recipients" to "service_role";

grant trigger on table "public"."local_entity_change_recipients" to "service_role";

grant truncate on table "public"."local_entity_change_recipients" to "service_role";

grant select on table "public"."local_entity_changes" to "authenticated";


  create policy "local_entity_changes_select_audience"
  on "public"."local_entity_changes"
  as permissive
  for select
  to authenticated
using ((audience_user_id = ( SELECT auth.uid() AS uid)));


CREATE TRIGGER local_entity_changes_address_tasks_example AFTER INSERT ON public.local_entity_changes FOR EACH ROW EXECUTE FUNCTION public.address_tasks_example_change();



revoke all on public.local_entity_change_recipients from anon, authenticated;

revoke all on function public.address_tasks_example_change()
  from public, anon, authenticated, service_role;
revoke all on function public.tasks_example_change_recipients(text, uuid, uuid)
  from public, anon, authenticated, service_role;

-- Changes recorded before this migration were judged when pulled. Address
-- each to the accounts that may read it now, which is what that judgment
-- would decide, so no device misses a change it has not pulled yet.
insert into public.local_entity_change_recipients (user_id, sequence)
select account.id, changes.sequence
from public.local_entity_changes changes
join auth.users account on account.id = changes.audience_user_id
on conflict do nothing;

insert into public.local_entity_change_recipients (user_id, sequence)
select distinct account.id, changes.sequence
from public.local_entity_changes changes
cross join lateral public.tasks_example_change_recipients(
  changes.entity_type,
  changes.entity_id,
  changes.owner_id
) recipient
join auth.users account on account.id = recipient.user_id
where changes.audience_user_id is null
on conflict do nothing;
