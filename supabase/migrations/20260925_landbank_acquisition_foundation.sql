-- LandBank Acquisition: parallel purchase-side engine
-- Existing origination tables are intentionally untouched.

create table if not exists public.lb_acq_assets (
  id uuid primary key default gen_random_uuid(),
  linked_site_id uuid references public.lb_sites(id) on delete set null,
  name text not null,
  country text not null check (country in ('England','Wales','Scotland','Republic of Ireland','Northern Ireland')),
  region text,
  county text,
  town text,
  postcode text,
  lat double precision,
  lng double precision,
  acreage_total numeric check (acreage_total is null or acreage_total >= 0),
  acreage_usable numeric check (acreage_usable is null or acreage_usable >= 0),
  asking_price numeric check (asking_price is null or asking_price >= 0),
  asking_price_gbp numeric check (asking_price_gbp is null or asking_price_gbp >= 0),
  currency text not null default 'GBP' check (currency in ('GBP','EUR')),
  sale_method text,
  tenure text,
  market_status text not null default 'on_market' check (market_status in ('on_market','off_market','auction','under_offer','withdrawn','sold','unknown')),
  source_name text,
  source_url text,
  source_ref text,
  listed_at date,
  source_checked_at timestamptz,
  agent_company text,
  agent_name text,
  agent_email text,
  agent_phone text,
  owner_name text,
  owner_organisation text,
  current_land_use text,
  agricultural_grade text,
  planning_status text,
  planning_reference text,
  planning_score numeric check (planning_score is null or planning_score between 0 and 100),
  grid_status text,
  grid_node_name text,
  grid_distance_km numeric check (grid_distance_km is null or grid_distance_km >= 0),
  grid_score numeric check (grid_score is null or grid_score between 0 and 100),
  terrain_score numeric check (terrain_score is null or terrain_score between 0 and 100),
  environmental_score numeric check (environmental_score is null or environmental_score between 0 and 100),
  land_score numeric check (land_score is null or land_score between 0 and 100),
  economics_score numeric check (economics_score is null or economics_score between 0 and 100),
  contactability_score numeric check (contactability_score is null or contactability_score between 0 and 100),
  acquisition_score numeric check (acquisition_score is null or acquisition_score between 0 and 100),
  score_confidence numeric check (score_confidence is null or score_confidence between 0 and 100),
  potential_mwp_low numeric check (potential_mwp_low is null or potential_mwp_low >= 0),
  potential_mwp_base numeric check (potential_mwp_base is null or potential_mwp_base >= 0),
  potential_mwp_high numeric check (potential_mwp_high is null or potential_mwp_high >= 0),
  land_cost_per_mwp numeric check (land_cost_per_mwp is null or land_cost_per_mwp >= 0),
  budget_cap_gbp numeric not null default 1000000 check (budget_cap_gbp > 0),
  screening_status text not null default 'unreviewed' check (screening_status in ('unreviewed','screening','pass','hold','reject')),
  hard_reject_reason text,
  priority_band text check (priority_band is null or priority_band in ('A','B','C','D')),
  stage text not null default 'discovered' check (stage in ('discovered','screening','viable','outreach_ready','contacted','agent_engaged','vendor_engaged','documents_requested','heads_of_terms','technical_dd','grid_dd','legal_dd','offer','exclusivity','exchange','acquired','rejected')),
  outreach_status text not null default 'not_contacted' check (outreach_status in ('not_contacted','email_sent','phoned','email_and_phoned','callback','interested','not_interested','do_not_contact','wrong_information')),
  outreach_selected_on date,
  outreach_sequence integer,
  first_contacted_at timestamptz,
  last_contacted_at timestamptz,
  replied_at timestamptz,
  next_action text,
  next_action_at timestamptz,
  do_not_contact boolean not null default false,
  screening_summary jsonb not null default '{}'::jsonb,
  flags jsonb not null default '[]'::jsonb,
  notes text,
  created_by text not null default 'landbank',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists lb_acq_assets_source_url_uidx on public.lb_acq_assets(source_url) where source_url is not null;
create index if not exists lb_acq_assets_country_stage_idx on public.lb_acq_assets(country, stage);
create index if not exists lb_acq_assets_score_idx on public.lb_acq_assets(acquisition_score desc nulls last, acreage_total desc nulls last);
create index if not exists lb_acq_assets_next_action_idx on public.lb_acq_assets(next_action_at) where next_action_at is not null;

create table if not exists public.lb_acq_tasks (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.lb_acq_assets(id) on delete cascade,
  type text not null default 'task',
  title text not null,
  notes text,
  due_at timestamptz,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  completed_at timestamptz,
  created_by text not null default 'landbank',
  created_at timestamptz not null default now()
);
create index if not exists lb_acq_tasks_due_idx on public.lb_acq_tasks(due_at) where completed_at is null;

create table if not exists public.lb_acq_activity (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.lb_acq_assets(id) on delete cascade,
  activity_type text not null,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_by text not null default 'landbank'
);
create index if not exists lb_acq_activity_asset_idx on public.lb_acq_activity(asset_id, occurred_at desc);

create table if not exists public.lb_acq_sources (
  id uuid primary key default gen_random_uuid(),
  country text not null,
  source_name text not null,
  source_type text not null,
  base_url text not null,
  active boolean not null default true,
  cadence text not null default 'daily',
  notes text,
  last_checked_at timestamptz,
  created_at timestamptz not null default now(),
  unique(country, source_name, base_url)
);

alter table public.lb_acq_assets enable row level security;
alter table public.lb_acq_tasks enable row level security;
alter table public.lb_acq_activity enable row level security;
alter table public.lb_acq_sources enable row level security;

drop policy if exists authenticated_acq_assets_access on public.lb_acq_assets;
create policy authenticated_acq_assets_access on public.lb_acq_assets
for all to authenticated
using ((select private.lb_access_allowed()))
with check ((select private.lb_access_allowed()));

drop policy if exists authenticated_acq_tasks_access on public.lb_acq_tasks;
create policy authenticated_acq_tasks_access on public.lb_acq_tasks
for all to authenticated
using ((select private.lb_access_allowed()))
with check ((select private.lb_access_allowed()));

drop policy if exists authenticated_acq_activity_access on public.lb_acq_activity;
create policy authenticated_acq_activity_access on public.lb_acq_activity
for all to authenticated
using ((select private.lb_access_allowed()))
with check ((select private.lb_access_allowed()));

drop policy if exists authenticated_acq_sources_access on public.lb_acq_sources;
create policy authenticated_acq_sources_access on public.lb_acq_sources
for all to authenticated
using ((select private.lb_access_allowed()))
with check ((select private.lb_access_allowed()));

revoke all on public.lb_acq_assets, public.lb_acq_tasks, public.lb_acq_activity, public.lb_acq_sources from anon;
grant select, insert, update on public.lb_acq_assets, public.lb_acq_tasks, public.lb_acq_activity, public.lb_acq_sources to authenticated;

create or replace view public.lb_acq_pipeline
with (security_invoker=true)
as
select
  a.*,
  case
    when a.asking_price_gbp is not null then a.asking_price_gbp <= a.budget_cap_gbp
    when a.currency = 'GBP' and a.asking_price is not null then a.asking_price <= a.budget_cap_gbp
    else null
  end as within_budget,
  case when a.acreage_total > 0 then round((a.acreage_total / 5.6)::numeric,1) end as gross_mwp_low,
  case when a.acreage_total > 0 then round((a.acreage_total / 4.8)::numeric,1) end as gross_mwp_mid,
  case when a.acreage_total > 0 then round((a.acreage_total / 4.0)::numeric,1) end as gross_mwp_high,
  case
    when coalesce(a.asking_price_gbp, case when a.currency='GBP' then a.asking_price end) is not null and a.acreage_total > 0
    then round((coalesce(a.asking_price_gbp, a.asking_price) / nullif(a.acreage_total / 4.8,0))::numeric,0)
  end as land_cost_per_gross_mw,
  row_number() over (
    order by coalesce(a.acquisition_score,0) desc, coalesce(a.grid_score,0) desc, coalesce(a.acreage_total,0) desc, a.created_at asc
  ) as acquisition_rank
from public.lb_acq_assets a;

create or replace view public.lb_acq_daily_queue
with (security_invoker=true)
as
select *
from public.lb_acq_pipeline
where screening_status = 'pass'
  and stage in ('viable','outreach_ready')
  and outreach_status = 'not_contacted'
  and do_not_contact = false
  and coalesce(acquisition_score,0) >= 60
  and coalesce(acreage_total,0) >= 100
  and (within_budget is true or asking_price is null)
order by acquisition_score desc nulls last, grid_score desc nulls last, acreage_total desc nulls last;

create or replace view public.lb_acq_todo
with (security_invoker=true)
as
select
  t.id as task_id, t.asset_id, t.type, t.title, t.notes, t.due_at, t.priority,
  a.name as asset_name, a.country, a.county, a.agent_name, a.agent_phone, a.agent_email,
  a.stage, a.acquisition_score
from public.lb_acq_tasks t
join public.lb_acq_assets a on a.id=t.asset_id
where t.completed_at is null;

create or replace view public.lb_acq_dashboard_metrics
with (security_invoker=true)
as
select
  count(*)::bigint as universe,
  count(*) filter (where screening_status='pass')::bigint as screening_pass,
  count(*) filter (where stage='outreach_ready')::bigint as outreach_ready,
  count(*) filter (where stage in ('agent_engaged','vendor_engaged'))::bigint as engaged,
  count(*) filter (where acquisition_score >= 80)::bigint as score_80_plus,
  count(*) filter (
    where case
      when asking_price_gbp is not null then asking_price_gbp <= budget_cap_gbp
      when currency='GBP' and asking_price is not null then asking_price <= budget_cap_gbp
      else false end
  )::bigint as under_budget,
  count(*) filter (where next_action_at is not null and next_action_at <= now())::bigint as actions_due
from public.lb_acq_assets;

grant select on public.lb_acq_pipeline, public.lb_acq_daily_queue, public.lb_acq_todo, public.lb_acq_dashboard_metrics to authenticated;
revoke all on public.lb_acq_pipeline, public.lb_acq_daily_queue, public.lb_acq_todo, public.lb_acq_dashboard_metrics from anon;

insert into public.lb_acq_sources(country,source_name,source_type,base_url,notes)
values
('England','Rightmove Commercial','portal','https://www.rightmove.co.uk/commercial-property-for-sale.html','Farms, estates and agricultural land'),
('England','OnTheMarket','portal','https://www.onthemarket.com/for-sale/farms-land/','Farms and land'),
('England','UK Land & Farms','portal','https://www.uklandandfarms.co.uk/','Specialist rural property'),
('Wales','Rightmove Commercial','portal','https://www.rightmove.co.uk/commercial-property-for-sale.html','Filter Wales + farms/land'),
('Wales','McCartneys','agent','https://www.mccartneys.co.uk/','Rural agency source'),
('Scotland','Galbraith','agent','https://www.galbraithgroup.com/','Farms, estates and rural land'),
('Scotland','Strutt & Parker Scotland','agent','https://www.struttandparker.com/','Farms and estates'),
('Republic of Ireland','Daft','portal','https://www.daft.ie/commercial-properties-for-sale/ireland/agricultural-land','Agricultural land'),
('Republic of Ireland','Property.ie','portal','https://www.property.ie/commercial-property/','Commercial/agricultural listings'),
('Republic of Ireland','MyHome.ie','portal','https://www.myhome.ie/commercial','Commercial/agricultural listings'),
('Northern Ireland','iamsold NI','auction','https://www.iamsoldni.com/','Auction and land listings')
on conflict (country,source_name,base_url) do nothing;
