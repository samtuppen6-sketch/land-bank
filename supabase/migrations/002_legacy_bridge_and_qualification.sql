-- LandBank v2: bridge the current CRM into the richer opportunity model.
-- Safe to run after 001_landbank_v2.sql.

alter table if exists public.lb_opportunities
  add column if not exists legacy_company_number text;

create unique index if not exists lb_opps_legacy_company_uq
  on public.lb_opportunities(legacy_company_number)
  where legacy_company_number is not null;

create unique index if not exists lb_sites_legacy_company_uq
  on public.lb_sites(legacy_company_number)
  where legacy_company_number is not null;

-- Structured qualification data: the facts that move a solar-land opportunity forward.
create table if not exists public.lb_qualifications (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null unique references public.lb_opportunities(id) on delete cascade,

  -- Land / control
  acres_available numeric,
  usable_acres numeric,
  contiguous boolean,
  ownership_confirmed boolean default false,
  occupier_or_tenant text,
  current_land_use text,
  access_notes text,

  -- Electricity / demand
  annual_consumption_kwh numeric,
  annual_electricity_cost numeric,
  current_tariff_p_per_kwh numeric,
  mpan text,
  half_hourly_data_available boolean,
  peak_daytime_kw numeric,
  three_phase_available boolean,
  supply_notes text,

  -- Commercial intent
  primary_objective text check (primary_objective in ('cost_saving','income','balanced','unknown')),
  repayment_preference_pct numeric check (repayment_preference_pct between 0 and 100),
  target_annual_income numeric,
  decision_process text,
  decision_makers text,

  -- Property / constraints
  mortgage_or_charge boolean,
  lender_name text,
  existing_solar_or_renewables text,
  lease_or_title_restrictions text,

  -- Process / evidence
  site_visit_at timestamptz,
  electricity_bills_received boolean default false,
  half_hourly_data_received boolean default false,
  letter_of_authority_received boolean default false,
  indicative_terms_issued boolean default false,
  heads_of_terms_issued boolean default false,
  documents_outstanding text,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.lb_stage_history (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.lb_opportunities(id) on delete cascade,
  from_stage text,
  to_stage text not null,
  reason text,
  changed_by text default 'sam',
  changed_at timestamptz default now()
);
create index if not exists lb_stage_history_opp_idx
  on public.lb_stage_history(opportunity_id, changed_at desc);

-- Import the CRM records that already exist in Supabase. This is deliberately
-- additive: the JSON prospect universe remains untouched and can be bulk-imported later.
insert into public.lb_organisations (
  company_number, name, organisation_type, sic_text, registered_address, created_at, updated_at
)
select
  fp.company_number,
  coalesce(nullif(fp.company_name,''), fp.company_number),
  'company',
  fp.sic_text,
  concat_ws(', ', nullif(fp.address_line,''), nullif(fp.town,''), nullif(fp.postcode,'')),
  now(), now()
from public.farm_prospects fp
where fp.company_number is not null
on conflict (company_number) do update set
  name = excluded.name,
  sic_text = coalesce(excluded.sic_text, public.lb_organisations.sic_text),
  registered_address = coalesce(excluded.registered_address, public.lb_organisations.registered_address),
  updated_at = now();

insert into public.lb_sites (
  legacy_company_number, name, address_line, town, county, postcode,
  lat, lng, location, acreage_total, parcel_count, created_at, updated_at
)
select
  fp.company_number,
  coalesce(nullif(fp.company_name,''), fp.company_number),
  fp.address_line,
  fp.town,
  fp.county,
  fp.postcode,
  fp.lat,
  fp.lng,
  case when fp.lat is not null and fp.lng is not null
       then st_setsrid(st_makepoint(fp.lng, fp.lat), 4326)::geography
       else null end,
  fp.acreage_est,
  coalesce(fp.land_title_count, 0),
  now(), now()
from public.farm_prospects fp
where fp.company_number is not null
on conflict (legacy_company_number) where legacy_company_number is not null do update set
  name = excluded.name,
  address_line = coalesce(excluded.address_line, public.lb_sites.address_line),
  town = coalesce(excluded.town, public.lb_sites.town),
  county = coalesce(excluded.county, public.lb_sites.county),
  postcode = coalesce(excluded.postcode, public.lb_sites.postcode),
  lat = coalesce(excluded.lat, public.lb_sites.lat),
  lng = coalesce(excluded.lng, public.lb_sites.lng),
  location = coalesce(excluded.location, public.lb_sites.location),
  acreage_total = coalesce(excluded.acreage_total, public.lb_sites.acreage_total),
  parcel_count = greatest(coalesce(excluded.parcel_count,0), coalesce(public.lb_sites.parcel_count,0)),
  updated_at = now();

insert into public.lb_opportunities (
  site_id, organisation_id, legacy_company_number, name, stage, loss_reason,
  probability, site_score, sales_score, commercial_score, priority_score,
  estimated_25y_value, probability_weighted_value,
  next_action, next_action_at, created_at, updated_at
)
select
  s.id,
  org.id,
  fp.company_number,
  coalesce(nullif(fp.company_name,''), fp.company_number) || ' solar opportunity',
  case fp.pipeline_status
    when 'new' then 'identified'
    when 'called' then 'outreach_started'
    when 'no_answer' then 'outreach_started'
    when 'interested' then 'qualified_interest'
    when 'warm' then 'commercial_assessment'
    when 'handed_over' then 'technical_dd'
    when 'live' then 'live'
    when 'not_interested' then 'closed_lost'
    when 'dead' then 'closed_lost'
    else 'identified'
  end,
  case when fp.pipeline_status in ('not_interested','dead') then fp.pipeline_status else null end,
  case fp.pipeline_status
    when 'new' then 3
    when 'called' then 10
    when 'no_answer' then 10
    when 'interested' then 25
    when 'warm' then 45
    when 'handed_over' then 75
    when 'live' then 100
    else 0
  end,
  fp.site_score,
  fp.sales_score,
  fp.commercial_score,
  fp.priority_score,
  fp.estimated_25y_value,
  fp.probability_weighted_value,
  fp.next_action,
  fp.next_action_at,
  now(), now()
from public.farm_prospects fp
join public.lb_sites s on s.legacy_company_number = fp.company_number
left join public.lb_organisations org on org.company_number = fp.company_number
where fp.company_number is not null
on conflict (legacy_company_number) where legacy_company_number is not null do update set
  organisation_id = coalesce(excluded.organisation_id, public.lb_opportunities.organisation_id),
  name = excluded.name,
  stage = case
    when public.lb_opportunities.stage in ('identified','researching','contact_ready') then excluded.stage
    else public.lb_opportunities.stage
  end,
  updated_at = now();

-- Seed known phone/email contact points from the live CRM overrides.
insert into public.lb_contact_points (
  organisation_id, type, value, label, is_primary, verification_status,
  discovery_method, provider, confidence, found_at
)
select org.id, 'phone', fp.phone, 'CRM phone', true,
       'probable', 'legacy_crm', 'LandBank legacy CRM', 70, now()
from public.farm_prospects fp
join public.lb_organisations org on org.company_number = fp.company_number
where fp.phone is not null and trim(fp.phone) <> ''
on conflict (type, value) do nothing;

insert into public.lb_contact_points (
  organisation_id, type, value, label, is_primary, verification_status,
  discovery_method, provider, confidence, found_at
)
select org.id, 'email', lower(fp.email), 'CRM email', true,
       'unknown', 'legacy_crm', 'LandBank legacy CRM', 50, now()
from public.farm_prospects fp
join public.lb_organisations org on org.company_number = fp.company_number
where fp.email is not null and trim(fp.email) <> ''
on conflict (type, value) do nothing;

-- Seed the qualification acreage we already capture.
insert into public.lb_qualifications (opportunity_id, acres_available, created_at, updated_at)
select o.id, fp.acreage_est, now(), now()
from public.farm_prospects fp
join public.lb_opportunities o on o.legacy_company_number = fp.company_number
where fp.acreage_est is not null
on conflict (opportunity_id) do update set
  acres_available = coalesce(excluded.acres_available, public.lb_qualifications.acres_available),
  updated_at = now();

-- A single view for the V2 UI / future AI assistant.
create or replace view public.lb_opportunity_workspace as
select
  o.id as opportunity_id,
  o.legacy_company_number,
  o.name as opportunity_name,
  o.stage,
  o.probability,
  o.sales_score,
  o.site_score,
  o.commercial_score,
  o.priority_score,
  o.estimated_25y_value,
  o.estimated_personal_25y_commission,
  o.probability_weighted_value,
  o.next_action,
  o.next_action_at,
  s.id as site_id,
  s.name as site_name,
  s.county,
  s.postcode,
  s.acreage_total,
  s.acreage_usable,
  s.parcel_count,
  s.potential_mwp,
  s.grid_score,
  s.planning_score,
  s.solar_score,
  s.ownership_score,
  org.id as organisation_id,
  org.name as organisation_name,
  org.company_number,
  q.annual_consumption_kwh,
  q.annual_electricity_cost,
  q.primary_objective,
  q.repayment_preference_pct,
  q.electricity_bills_received,
  q.half_hourly_data_received,
  q.documents_outstanding
from public.lb_opportunities o
join public.lb_sites s on s.id = o.site_id
left join public.lb_organisations org on org.id = o.organisation_id
left join public.lb_qualifications q on q.opportunity_id = o.id;
