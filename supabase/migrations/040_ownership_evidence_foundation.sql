create table if not exists public.lb_ownership_evidence (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  organisation_id uuid references public.lb_organisations(id) on delete cascade,
  person_id uuid references public.lb_people(id) on delete cascade,
  evidence_type text not null check(evidence_type in ('title_company_number_exact','title_owner_name_exact','title_relationship_confirmed','registered_address_company_match','probable_operator_match','speculative_match','manual_verified')),
  confidence numeric not null check(confidence between 0 and 100),
  source text not null,
  source_ref text,
  details jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique(site_id,organisation_id,evidence_type,source,source_ref)
);
create index if not exists lb_ownership_evidence_site_idx on public.lb_ownership_evidence(site_id,confidence desc);
create index if not exists lb_ownership_evidence_org_idx on public.lb_ownership_evidence(organisation_id);

create table if not exists public.lb_title_polygons (
  id uuid primary key default gen_random_uuid(),inspire_id text unique,title_number text,tenure text,
  geometry geometry(Geometry,4326) not null,source_date date,source text not null default 'HM Land Registry INSPIRE Index Polygons',source_ref text,raw_data jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists lb_title_polygons_geom_gix on public.lb_title_polygons using gist(geometry);
create index if not exists lb_title_polygons_title_idx on public.lb_title_polygons(title_number);

create table if not exists public.lb_corporate_title_owners (
  id uuid primary key default gen_random_uuid(),title_number text not null,company_number text,proprietor_name text,tenure text,proprietor_address text,
  source text not null default 'HM Land Registry corporate ownership data',source_date date,raw_data jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),
  unique(title_number,company_number,proprietor_name)
);
create index if not exists lb_corporate_title_owners_title_idx on public.lb_corporate_title_owners(title_number);
create index if not exists lb_corporate_title_owners_company_idx on public.lb_corporate_title_owners(company_number);

create table if not exists public.lb_site_title_matches (
  site_id uuid not null references public.lb_sites(id) on delete cascade,title_polygon_id uuid not null references public.lb_title_polygons(id) on delete cascade,
  match_method text not null default 'point_intersection',confidence numeric not null default 65 check(confidence between 0 and 100),matched_at timestamptz not null default now(),primary key(site_id,title_polygon_id)
);
create index if not exists lb_site_title_matches_site_idx on public.lb_site_title_matches(site_id);

create or replace function public.lb_recalculate_ownership_score(p_site_id uuid)
returns numeric language plpgsql security definer set search_path=public as $$
declare v_score numeric;begin
  select max(confidence) into v_score from public.lb_ownership_evidence where site_id=p_site_id;
  update public.lb_sites set ownership_score=v_score,updated_at=now() where id=p_site_id;
  perform public.lb_recalculate_site_score(p_site_id);return v_score;
end;$$;

insert into public.lb_ownership_evidence(site_id,organisation_id,evidence_type,confidence,source,source_ref,details)
select s.id,o.id,'probable_operator_match',45,'LandBank legacy land/company source',s.legacy_company_number,jsonb_build_object('reason','Legacy land/company association; legal title ownership not yet confirmed')
from public.lb_sites s join public.lb_organisations o on o.company_number=s.legacy_company_number where s.legacy_company_number is not null
on conflict(site_id,organisation_id,evidence_type,source,source_ref) do nothing;

insert into public.lb_site_parties(site_id,organisation_id,relationship,confidence,source,source_ref,verified_at)
select s.id,o.id,'probable_owner',45,'LandBank legacy land/company source',s.legacy_company_number,null
from public.lb_sites s join public.lb_organisations o on o.company_number=s.legacy_company_number
where s.legacy_company_number is not null and not exists(select 1 from public.lb_site_parties p where p.site_id=s.id and p.organisation_id=o.id and p.relationship='probable_owner');

update public.lb_sites s set ownership_score=e.score,updated_at=now()
from (select site_id,max(confidence) score from public.lb_ownership_evidence group by site_id)e where s.id=e.site_id;

create or replace view public.lb_ownership_progress as
select count(*) total_sites,count(*) filter(where ownership_score>=95) title_confirmed,count(*) filter(where ownership_score>=80 and ownership_score<95) strong,count(*) filter(where ownership_score>=60 and ownership_score<80) medium,count(*) filter(where ownership_score>0 and ownership_score<60) provisional,count(*) filter(where ownership_score is null) unknown,round(avg(ownership_score),1) mean_confidence from public.lb_sites;
grant select on public.lb_ownership_progress to anon,authenticated;

create or replace view public.lb_ownership_gaps as
select s.id site_id,s.name,s.legacy_company_number,s.county,s.postcode,s.parcel_count,s.ownership_score,s.site_score,s.grid_score,s.solar_score,o.id opportunity_id,o.stage,o.priority_score,o.next_action,o.next_action_at,
case when s.ownership_score is null then 'No ownership evidence' when s.ownership_score<60 then 'Confirm title/legal owner' when s.ownership_score<85 then 'Strengthen owner/title relationship' else 'Ownership sufficiently strong for screening' end ownership_next_action
from public.lb_sites s left join public.lb_opportunities o on o.site_id=s.id where coalesce(s.ownership_score,0)<85 order by coalesce(o.priority_score,s.site_score,0) desc,s.parcel_count desc;
grant select on public.lb_ownership_gaps to anon,authenticated;

revoke all on public.lb_ownership_evidence,public.lb_title_polygons,public.lb_corporate_title_owners,public.lb_site_title_matches from anon,authenticated;
revoke all on function public.lb_recalculate_ownership_score(uuid) from public,anon,authenticated;
grant execute on function public.lb_recalculate_ownership_score(uuid) to service_role;
