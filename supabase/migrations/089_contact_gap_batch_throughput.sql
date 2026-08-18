create or replace function public.lb_kick_contact_gap_batch(p_provider text default null,p_batch integer default 2)
returns bigint language plpgsql security definer set search_path=public,net as $$
declare
  v_request_id bigint;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhkb3FjbHJ3ZGR1bmNqYXh0aXhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwMjkyNjMsImV4cCI6MjA5NjYwNTI2M30.vLCzN7-eNJh32tvy0zySDGX5bp6X1v9WlST59BSmIkk';
begin
  if p_provider is not null and p_provider not in ('google_places','hunter') then raise exception 'invalid provider'; end if;
  select net.http_post(
    url := 'https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/process-contact-gap-batch',
    body := jsonb_strip_nulls(jsonb_build_object('batch_size',greatest(1,least(10,p_batch)),'provider',p_provider)),
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer '||v_anon),
    timeout_milliseconds := 120000
  ) into v_request_id;
  return v_request_id;
end;$$;

revoke all on function public.lb_kick_contact_gap_batch(text,integer) from public,anon,authenticated;
grant execute on function public.lb_kick_contact_gap_batch(text,integer) to service_role;