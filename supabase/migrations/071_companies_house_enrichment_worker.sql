create or replace function public.lb_batch_key_valid(p_key text)
returns boolean
language sql
security definer
set search_path='vault'
as $$
  select exists(
    select 1
    from vault.decrypted_secrets
    where name='landbank_batch_key'
      and decrypted_secret=p_key
  );
$$;

revoke all on function public.lb_batch_key_valid(text) from public,anon,authenticated;
grant execute on function public.lb_batch_key_valid(text) to service_role;

create or replace function public.lb_kick_companies_house_batch(p_batch_size integer default 50)
returns bigint
language plpgsql
security definer
set search_path = 'public', 'net', 'vault'
as $$
declare
  v_key text;
  v_request_id bigint;
begin
  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name = 'landbank_batch_key'
  limit 1;

  if v_key is null then
    raise exception 'landbank_batch_key missing';
  end if;

  select net.http_post(
    url := 'https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/companies-house-batch',
    body := jsonb_build_object('limit', greatest(1, least(100, p_batch_size))),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-landbank-batch-key', v_key
    ),
    timeout_milliseconds := 120000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.lb_kick_companies_house_batch(integer) from public,anon,authenticated;
grant execute on function public.lb_kick_companies_house_batch(integer) to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname='landbank-companies-house-enrichment') then
    perform cron.unschedule('landbank-companies-house-enrichment');
  end if;
end $$;

select cron.schedule(
  'landbank-companies-house-enrichment',
  '*/5 * * * *',
  'select public.lb_kick_companies_house_batch(50);'
);
