alter table public.lb_organisations
  add column if not exists psc_checked_at timestamptz;

create table if not exists public.lb_company_controls(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.lb_organisations(id) on delete cascade,
  controller_type text not null,
  name text not null,
  nature_of_control text[] not null default '{}',
  notified_on date,
  ceased_on date,
  is_active boolean not null default true,
  nationality text,
  country_of_residence text,
  registration_number text,
  address text,
  source text not null default 'companies_house_psc',
  source_ref text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id,source_ref)
);

create index if not exists lb_company_controls_org_active_idx
  on public.lb_company_controls(organisation_id,is_active);

alter table public.lb_company_controls enable row level security;
drop policy if exists "lb_company_controls_read" on public.lb_company_controls;
create policy "lb_company_controls_read" on public.lb_company_controls
  for select to anon,authenticated using (true);
grant select on public.lb_company_controls to anon,authenticated;
grant all on public.lb_company_controls to service_role;

create or replace view public.lb_company_controller_summary as
select
  organisation_id,
  string_agg(name || case when controller_type='individual' then ' (PSC)' else ' (PSC entity)' end, ', ' order by (controller_type='individual') desc, name) as company_controllers,
  string_agg(name, ', ' order by name) filter(where controller_type='individual') as individual_controllers,
  count(*) filter(where controller_type='individual')::integer as individual_controller_count,
  count(*)::integer as controller_count
from public.lb_company_controls
where is_active
group by organisation_id;

grant select on public.lb_company_controller_summary to anon,authenticated;

create or replace function public.lb_kick_companies_house_psc_batch(p_batch_size integer default 25)
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
    url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/companies-house-psc-batch',
    body:=jsonb_build_object('limit',greatest(1,least(50,p_batch_size))),
    headers:=jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),
    timeout_milliseconds:=120000
  ) into v_request_id;
  return v_request_id;
end;$$;

revoke all on function public.lb_kick_companies_house_psc_batch(integer) from public,anon,authenticated;
grant execute on function public.lb_kick_companies_house_psc_batch(integer) to service_role;

do $$
begin
  if exists(select 1 from cron.job where jobname='landbank-companies-house-psc') then
    perform cron.unschedule('landbank-companies-house-psc');
  end if;
end $$;

select cron.schedule(
  'landbank-companies-house-psc',
  '*/5 * * * *',
  'select public.lb_kick_companies_house_psc_batch(25);'
);
