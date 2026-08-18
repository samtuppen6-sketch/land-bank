alter table public.lb_organisations
  add column if not exists domain_source text,
  add column if not exists domain_confidence numeric check (domain_confidence is null or (domain_confidence>=0 and domain_confidence<=100)),
  add column if not exists domain_checked_at timestamptz;

create index if not exists lb_organisations_domain_pending_idx
  on public.lb_organisations(domain_checked_at)
  where domain is null;

create or replace function public.lb_kick_contact_enrichment_batch(p_batch_size integer default 1, p_min_priority numeric default 85)
returns bigint
language plpgsql
security definer
set search_path='public','net','vault'
as $$
declare
  v_key text;
  v_request_id bigint;
begin
  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='landbank_batch_key'
  limit 1;
  if v_key is null then raise exception 'landbank_batch_key missing'; end if;

  select net.http_post(
    url := 'https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/contact-enrichment-batch',
    body := jsonb_build_object(
      'limit', greatest(1,least(5,p_batch_size)),
      'min_priority', greatest(0,least(100,p_min_priority))
    ),
    headers := jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),
    timeout_milliseconds := 120000
  ) into v_request_id;
  return v_request_id;
end;
$$;

revoke all on function public.lb_kick_contact_enrichment_batch(integer,numeric) from public,anon,authenticated;
grant execute on function public.lb_kick_contact_enrichment_batch(integer,numeric) to service_role;

-- Intentionally no cron schedule here. This worker can consume paid Google/Hunter API usage
-- and should remain operator-triggered until spend limits are explicitly approved.
