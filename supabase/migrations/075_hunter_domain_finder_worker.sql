create or replace function public.lb_kick_domain_finder_batch(p_batch_size integer default 25,p_min_priority numeric default 80)
returns bigint
language plpgsql
security definer
set search_path='public','net','vault'
as $$
declare v_key text;v_request_id bigint;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name='landbank_batch_key' limit 1;
  if v_key is null then raise exception 'landbank_batch_key missing'; end if;
  select net.http_post(
    url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/domain-finder-batch',
    body:=jsonb_build_object('limit',greatest(1,least(50,p_batch_size)),'min_priority',greatest(0,least(100,p_min_priority))),
    headers:=jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),
    timeout_milliseconds:=120000
  ) into v_request_id;
  return v_request_id;
end;$$;

revoke all on function public.lb_kick_domain_finder_batch(integer,numeric) from public,anon,authenticated;
grant execute on function public.lb_kick_domain_finder_batch(integer,numeric) to service_role;

do $$
begin
  if exists(select 1 from cron.job where jobname='landbank-domain-finder-enrichment') then
    perform cron.unschedule('landbank-domain-finder-enrichment');
  end if;
end $$;

select cron.schedule(
  'landbank-domain-finder-enrichment',
  '*/5 * * * *',
  'select public.lb_kick_domain_finder_batch(25,80);'
);
