-- Requires a Supabase Vault secret named landbank_batch_key.
-- The deployed project currently has this secret configured.

create or replace function public.lb_kick_solar_batch(p_batch_size integer default 10)
returns bigint
language plpgsql
security definer
set search_path=public,net,vault
as $$
declare
  v_key text;
  v_request_id bigint;
begin
  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='landbank_batch_key'
  limit 1;

  if v_key is null then
    raise exception 'landbank_batch_key is missing from Supabase Vault';
  end if;

  select net.http_post(
    url := 'https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/assess-solar-batch',
    body := jsonb_build_object('batch_size',greatest(1,least(15,coalesce(p_batch_size,10)))),
    headers := jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.lb_kick_solar_batch(integer) from public,anon,authenticated;
grant execute on function public.lb_kick_solar_batch(integer) to service_role;
