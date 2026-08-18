create or replace function public.lb_kick_web_crawl_batch()
returns bigint
language plpgsql
security definer
set search_path=public,net,cron
as $$
declare
  v_request_id bigint;
  v_remaining integer;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhkb3FjbHJ3ZGR1bmNqYXh0aXhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwMjkyNjMsImV4cCI6MjA5NjYwNTI2M30.vLCzN7-eNJh32tvy0zySDGX5bp6X1v9WlST59BSmIkk';
begin
  update public.lb_web_crawl_jobs
     set status='queued', locked_at=null, updated_at=now(),
         last_error=coalesce(last_error,'') || case when coalesce(last_error,'')='' then '' else ' | ' end || 'stale processing lease reset'
   where status='processing' and locked_at < now()-interval '15 minutes';

  select count(*) into v_remaining from public.lb_web_crawl_jobs where status in ('queued','processing');
  if v_remaining=0 then
    begin perform cron.unschedule('landbank-website-contact-crawl'); exception when others then null; end;
    return null;
  end if;

  select net.http_post(
    url := 'https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/crawl-web-batch',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon),
    timeout_milliseconds := 120000
  ) into v_request_id;
  return v_request_id;
end;$$;
select public.lb_kick_web_crawl_batch();
