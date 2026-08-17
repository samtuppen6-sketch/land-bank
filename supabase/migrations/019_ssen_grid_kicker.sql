create or replace function public.lb_kick_ssen_grid_import()
returns bigint
language plpgsql
security definer
set search_path=public,net,vault
as $$
declare v_key text;v_request_id bigint;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name='landbank_batch_key' limit 1;
  if v_key is null then raise exception 'landbank_batch_key is missing from Supabase Vault';end if;
  select net.http_post(
    url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/import-ssen-grid',
    body:='{}'::jsonb,
    headers:=jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),
    timeout_milliseconds:=60000
  ) into v_request_id;
  return v_request_id;
end;$$;
revoke all on function public.lb_kick_ssen_grid_import() from public,anon,authenticated;
grant execute on function public.lb_kick_ssen_grid_import() to service_role;
