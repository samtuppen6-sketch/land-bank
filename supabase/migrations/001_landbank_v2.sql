-- LandBank v2 foundation
-- Non-destructive extension of the current farm_prospects / farm_activity CRM.
-- Designed for Supabase Postgres with PostGIS available.

create extension if not exists postgis;

-- Keep the existing farm_prospects table useful while v2 objects are introduced.
alter table if exists public.farm_prospects
  add column if not exists site_score numeric,
  add column if not exists sales_score numeric,
  add column if not exists ownership_score numeric,
  add column if not exists commercial_score numeric,
  add column if not exists priority_score numeric,
  add column if not exists potential_mwp numeric,
  add column if not exists estimated_annual_mwh numeric,
  add column if not exists estimated_25y_value numeric,
  add column if not exists probability_weighted_value numeric,
  add column if not exists next_action text,
  add column if not exists next_action_at timestamptz,
  add column if not exists loss_reason text,
  add column if not exists last_enriched_at timestamptz;

create table if not exists public.lb_sites (
  id uuid primary key default gen_random_uuid(),
  legacy_company_number text,
  name text not null,
  address_line text,
  town text,
  county text,
  postcode text,
  lat double precision,
  lng double precision,
  location geography(point, 4326),
  acreage_total numeric,
  acreage_usable numeric,
  parcel_count integer default 0,
  potential_mwp numeric,
  site_score numeric,
  grid_score numeric,
  planning_score numeric,
  solar_score numeric,
  land_score numeric,
  environmental_score numeric,
  ownership_score numeric,
  overall_priority_score numeric,
  data_confidence numeric,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists lb_sites_location_gix on public.lb_sites using gist(location);
create index if not exists lb_sites_company_idx on public.lb_sites(legacy_company_number);
create index if not exists lb_sites_priority_idx on public.lb_sites(overall_priority_score desc nulls last);

create table if not exists public.lb_parcels (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  title_number text,
  inspire_id text,
  tenure text,
  area_acres numeric,
  agricultural_grade text,
  land_use text,
  geometry geometry(multipolygon, 4326),
  source text,
  source_ref text,
  source_confidence numeric,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists lb_parcels_geom_gix on public.lb_parcels using gist(geometry);
create index if not exists lb_parcels_site_idx on public.lb_parcels(site_id);

create table if not exists public.lb_organisations (
  id uuid primary key default gen_random_uuid(),
  company_number text unique,
  name text not null,
  organisation_type text,
  company_status text,
  sic_text text,
  registered_address text,
  website text,
  domain text,
  companies_house_updated_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.lb_people (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  first_name text,
  last_name text,
  occupation text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.lb_organisation_people (
  organisation_id uuid not null references public.lb_organisations(id) on delete cascade,
  person_id uuid not null references public.lb_people(id) on delete cascade,
  role text,
  appointed_on date,
  resigned_on date,
  is_primary boolean default false,
  source text default 'companies_house',
  primary key (organisation_id, person_id, role)
);

create table if not exists public.lb_site_parties (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  organisation_id uuid references public.lb_organisations(id) on delete cascade,
  person_id uuid references public.lb_people(id) on delete cascade,
  relationship text not null check (relationship in ('registered_owner','probable_owner','operator','occupier','tenant','land_agent','unknown')),
  confidence numeric check (confidence between 0 and 100),
  source text,
  source_ref text,
  verified_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists lb_site_parties_site_idx on public.lb_site_parties(site_id);

create table if not exists public.lb_contact_points (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid references public.lb_organisations(id) on delete cascade,
  person_id uuid references public.lb_people(id) on delete cascade,
  type text not null check (type in ('phone','mobile','email','website','linkedin','other')),
  value text not null,
  label text,
  is_primary boolean default false,
  verification_status text default 'unknown' check (verification_status in ('verified','probable','catch_all','unknown','invalid')),
  discovery_method text,
  provider text,
  source_url text,
  confidence numeric check (confidence between 0 and 100),
  found_at timestamptz default now(),
  verified_at timestamptz,
  do_not_contact boolean default false,
  unique(type, value)
);
create index if not exists lb_contact_org_idx on public.lb_contact_points(organisation_id);
create index if not exists lb_contact_person_idx on public.lb_contact_points(person_id);

create table if not exists public.lb_opportunities (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  organisation_id uuid references public.lb_organisations(id),
  name text not null,
  stage text not null default 'identified' check (stage in (
    'identified','researching','contact_ready','outreach_started','connected',
    'qualified_interest','site_data_requested','site_prescreen','commercial_assessment',
    'proposal','site_visit','heads_of_terms','technical_dd','grid_planning',
    'finance_approval','contracted','construction','commissioned','live',
    'closed_lost'
  )),
  loss_reason text,
  owner_name text default 'sam',
  probability numeric default 0 check (probability between 0 and 100),
  sales_score numeric,
  site_score numeric,
  commercial_score numeric,
  priority_score numeric,
  estimated_capex numeric,
  estimated_annual_revenue numeric,
  estimated_25y_value numeric,
  estimated_personal_annual_commission numeric,
  estimated_personal_25y_commission numeric,
  probability_weighted_value numeric,
  next_action text,
  next_action_at timestamptz,
  last_contacted_at timestamptz,
  stale_after_days integer default 14,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists lb_opps_stage_idx on public.lb_opportunities(stage);
create index if not exists lb_opps_next_idx on public.lb_opportunities(next_action_at);
create index if not exists lb_opps_priority_idx on public.lb_opportunities(priority_score desc nulls last);
create index if not exists lb_opps_weighted_idx on public.lb_opportunities(probability_weighted_value desc nulls last);

create table if not exists public.lb_tasks (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.lb_opportunities(id) on delete cascade,
  site_id uuid references public.lb_sites(id) on delete cascade,
  type text default 'task',
  title text not null,
  notes text,
  due_at timestamptz,
  completed_at timestamptz,
  priority text default 'normal' check (priority in ('low','normal','high','urgent')),
  created_by text default 'sam',
  created_at timestamptz default now()
);
create index if not exists lb_tasks_due_idx on public.lb_tasks(due_at) where completed_at is null;

create table if not exists public.lb_site_assessments (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  assessment_type text not null check (assessment_type in ('grid','planning','environment','solar','land','ownership')),
  score numeric check (score between 0 and 100),
  status text,
  raw_data jsonb default '{}'::jsonb,
  summary jsonb default '{}'::jsonb,
  provider text,
  source_ref text,
  assessed_at timestamptz default now(),
  unique(site_id, assessment_type, provider)
);

create table if not exists public.lb_financial_scenarios (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.lb_opportunities(id) on delete cascade,
  name text not null,
  system_mwp numeric,
  annual_generation_mwh numeric,
  self_consumption_pct numeric,
  repayment_allocation_pct numeric,
  finance_amount numeric,
  finance_rate_pct numeric,
  estimated_repayment_years numeric,
  farmer_income_year_1 numeric,
  farmer_income_25y numeric,
  gross_project_revenue_25y numeric,
  participation_pool_pct numeric default 10,
  personal_share_of_pool_pct numeric default 20,
  personal_commission_year_1 numeric,
  personal_commission_25y numeric,
  assumptions jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.lb_enrichment_events (
  id uuid primary key default gen_random_uuid(),
  prospect_key text,
  organisation_id uuid references public.lb_organisations(id) on delete cascade,
  site_id uuid references public.lb_sites(id) on delete cascade,
  provider text not null,
  enrichment_type text not null,
  status text not null,
  confidence numeric,
  source_ref text,
  payload jsonb default '{}'::jsonb,
  error_message text,
  created_at timestamptz default now()
);
create index if not exists lb_enrichment_key_idx on public.lb_enrichment_events(prospect_key, created_at desc);

-- A compact management view for the future dashboard.
create or replace view public.lb_pipeline_summary as
select
  stage,
  count(*) as opportunities,
  coalesce(sum(estimated_25y_value),0) as gross_25y_value,
  coalesce(sum(estimated_personal_25y_commission),0) as personal_25y_commission,
  coalesce(sum(probability_weighted_value),0) as weighted_value,
  count(*) filter (where next_action_at < now()) as overdue_actions
from public.lb_opportunities
group by stage;

-- Useful view for records that require immediate attention.
create or replace view public.lb_needs_attention as
select o.*
from public.lb_opportunities o
where o.stage not in ('commissioned','live','closed_lost')
  and (
    o.next_action is null
    or o.next_action_at is null
    or o.next_action_at < now()
    or (o.last_contacted_at is not null and o.last_contacted_at < now() - make_interval(days => o.stale_after_days))
  )
order by o.priority_score desc nulls last, o.next_action_at asc nulls first;
