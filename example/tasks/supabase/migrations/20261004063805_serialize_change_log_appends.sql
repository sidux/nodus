set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.serialize_local_entity_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nodus.local_entity_changes', 0));
  return null;
end;
$function$
;

CREATE TRIGGER local_entity_changes_serialize BEFORE INSERT ON public.local_entity_changes FOR EACH STATEMENT EXECUTE FUNCTION public.serialize_local_entity_changes();

revoke all on function public.serialize_local_entity_changes() from public, anon, authenticated, service_role;
