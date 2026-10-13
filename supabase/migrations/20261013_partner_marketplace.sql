-- LandBank Partner Market: capital and delivery lanes
-- Applied to production on 2026-10-13. This file keeps the schema change in source control.

create table if not exists public.lb_partner_organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  partner_lane text not null check (partner_lane in ('capital','delivery')),
  partner_type text not null,
  website text,
  coverage text[] not null default '{}',
  technologies text[] not null default array['solar']::text[],
  status text not null default 'research' check (status in ('research','qualified','priority','active','not_fit','paused')),
  priority_score numeric(5,2),
  source_url text,
  source_checked_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lb_partner_contacts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.lb_partner_organisations(id) on delete cascade,
  full_name text,
  job_title text,
  email text,
  phone text,
  linkedin_url text,
  is_primary boolean not null default false,
  verification_status text not null default 'unverified',
  source_url text,
  last_verified_at timestamptz,
  do_not_contact boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lb_partner_mandates (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null unique references public.lb_partner_organisations(id) on delete cascade,
  geographies text[] not null default '{}',
  technologies text[] not null default array['solar']::text[],
  min_mw numeric,
  max_mw numeric,
  stage_min_rank integer not null default 1 check (stage_min_rank between 1 and 5),
  stage_max_rank integer not null default 5 check (stage_max_rank between 1 and 5),
  earliest_stage text,
  latest_stage text,
  land_control_requirement text,
  grid_requirement text,
  planning_requirement text,
  funds_devex boolean,
  capital_min_gbp numeric,
  capital_max_gbp numeric,
  structures text[] not null default '{}',
  control_requirements text,
  originator_economics text,
  review_requirements text,
  evidence_url text,
  last_verified_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lb_partner_outreach (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.lb_partner_organisations(id) on delete cascade,
  contact_id uuid references public.lb_partner_contacts(id) on delete set null,
  lane text not null check (lane in ('capital','delivery')),
  channel text not null default 'email',
  direction text not null default 'outbound' check (direction in ('outbound','inbound')),
  status text not null default 'draft' check (status in ('draft','approved','sent','replied','declined','paused')),
  review_status text not null default 'approval_required' check (review_status in ('approval_required','approved','not_required')),
  subject text,
  message_excerpt text,
  provider_message_id text,
  thread_id text,
  occurred_at timestamptz,
  next_action text,
  next_action_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.lb_partner_organisations enable row level security;
alter table public.lb_partner_contacts enable row level security;
alter table public.lb_partner_mandates enable row level security;
alter table public.lb_partner_outreach enable row level security;

drop policy if exists "partner_org_authenticated" on public.lb_partner_organisations;
create policy "partner_org_authenticated" on public.lb_partner_organisations for all to authenticated using (true) with check (true);
drop policy if exists "partner_contacts_authenticated" on public.lb_partner_contacts;
create policy "partner_contacts_authenticated" on public.lb_partner_contacts for all to authenticated using (true) with check (true);
drop policy if exists "partner_mandates_authenticated" on public.lb_partner_mandates;
create policy "partner_mandates_authenticated" on public.lb_partner_mandates for all to authenticated using (true) with check (true);
drop policy if exists "partner_outreach_authenticated" on public.lb_partner_outreach;
create policy "partner_outreach_authenticated" on public.lb_partner_outreach for all to authenticated using (true) with check (true);

grant select, insert, update, delete on public.lb_partner_organisations to authenticated;
grant select, insert, update, delete on public.lb_partner_contacts to authenticated;
grant select, insert, update, delete on public.lb_partner_mandates to authenticated;
grant select, insert, update, delete on public.lb_partner_outreach to authenticated;

create or replace view public.lb_partner_directory with (security_invoker = true) as
select o.id,o.name,o.partner_lane,o.partner_type,o.website,o.coverage,o.status,o.priority_score,o.source_url,o.source_checked_at,
c.full_name primary_contact,c.job_title primary_contact_title,c.email primary_email,c.phone primary_phone,c.linkedin_url primary_linkedin,c.verification_status contact_verification_status,
m.geographies,m.technologies,m.min_mw,m.max_mw,m.stage_min_rank,m.stage_max_rank,m.earliest_stage,m.latest_stage,m.land_control_requirement,m.grid_requirement,m.planning_requirement,
m.funds_devex,m.capital_min_gbp,m.capital_max_gbp,m.structures,m.control_requirements,m.originator_economics,m.review_requirements,m.evidence_url mandate_evidence_url,
m.last_verified_at mandate_verified_at,o.notes
from public.lb_partner_organisations o
left join lateral (
  select pc.* from public.lb_partner_contacts pc
  where pc.organisation_id=o.id and pc.do_not_contact=false
  order by pc.is_primary desc,pc.last_verified_at desc nulls last,pc.created_at limit 1
) c on true
left join public.lb_partner_mandates m on m.organisation_id=o.id;

grant select on public.lb_partner_directory to authenticated;
revoke all on public.lb_partner_directory from anon;

create or replace view public.lb_partner_matches with (security_invoker = true) as
with assets as (
 select a.id asset_id,a.name asset_name,a.country,a.county,a.potential_mwp_base,a.priority_band,a.stage,a.asset_class,
 case when a.asset_class='raw_land' then 1 when a.asset_class in ('land_with_rights','project_rights') then 2
      when a.asset_class='consented_project' then 3 when a.asset_class='ready_to_build' then 4 when a.stage='operating' then 5 else 1 end stage_rank
 from public.lb_acq_assets a
)
select a.*,d.id organisation_id,d.name organisation_name,d.partner_lane,d.partner_type,d.primary_contact,d.primary_email,d.primary_phone,d.earliest_stage,d.latest_stage,d.funds_devex,
(
 case when coalesce(array_length(d.geographies,1),0)=0 then 10 when a.country=any(d.geographies) then 40
      when a.country in ('England','Wales','Scotland','Northern Ireland') and 'UK'=any(d.geographies) then 40
      when a.country='Republic of Ireland' and ('Ireland'=any(d.geographies) or 'Republic of Ireland'=any(d.geographies)) then 40 else 0 end
 + case when a.potential_mwp_base is null then 5
        when d.min_mw is null and d.max_mw is null then 10
        when (d.min_mw is null or a.potential_mwp_base>=d.min_mw) and (d.max_mw is null or a.potential_mwp_base<=d.max_mw) then 30 else 0 end
 + case when a.stage_rank between coalesce(d.stage_min_rank,1) and coalesce(d.stage_max_rank,5)
        then case when coalesce(d.stage_min_rank,1)=1 and coalesce(d.stage_max_rank,5)=5 then 10 else 20 end
        else 0 end
 + case when coalesce(array_length(d.technologies,1),0)=0 or 'solar'=any(d.technologies) then 10 else 0 end
)::integer match_score
from assets a cross join public.lb_partner_directory d
where d.status in ('qualified','priority','active');

grant select on public.lb_partner_matches to authenticated;
revoke all on public.lb_partner_matches from anon;

create index if not exists lb_partner_org_lane_status_idx on public.lb_partner_organisations(partner_lane,status);
create index if not exists lb_partner_contacts_org_idx on public.lb_partner_contacts(organisation_id);
create index if not exists lb_partner_outreach_org_idx on public.lb_partner_outreach(organisation_id,created_at desc);
