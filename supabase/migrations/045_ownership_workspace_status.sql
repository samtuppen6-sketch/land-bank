-- Evidence-led ownership reporting for the CRM.
-- Manual qualification flags remain separate from authoritative HMLR evidence.

create or replace view public.lb_ownership_workspace as
select
  s.id as site_id,
  s.legacy_company_number,
  s.name as site_name,
  s.postcode,
  s.ownership_score,
  case
    when coalesce(s.ownership_score,0) >= 100 then 'title_spatial_confirmed'
    when coalesce(s.ownership_score,0) >= 85 and coalesce(x.inspire_point_hits,0) > 0 then 'strong_ccod_plus_inspire'
    when coalesce(s.ownership_score,0) >= 85 then 'strong_ccod'
    when coalesce(s.ownership_score,0) > 0 then 'provisional'
    else 'unknown'
  end as ownership_status,
  coalesce(x.ccod_title_count,0) as ccod_title_count,
  coalesce(x.inspire_point_hits,0) as inspire_point_hit_count,
  coalesce(x.resolved_spatial_title_count,0) as resolved_spatial_title_count,
  coalesce(x.inspire_ids,'[]'::jsonb) as inspire_ids,
  coalesce(x.ccod_titles,'[]'::jsonb) as ccod_titles
from public.lb_sites s
left join lateral (
  select
    (select count(*) from public.lb_ownership_evidence e
      where e.site_id=s.id and e.evidence_type='title_relationship_confirmed' and e.confidence>=85) as ccod_title_count,
    (select count(*) from public.lb_ownership_evidence e
      where e.site_id=s.id and e.evidence_type='inspire_spatial_point_match') as inspire_point_hits,
    (select count(*) from public.lb_ownership_evidence e
      where e.site_id=s.id and e.evidence_type='title_company_number_exact' and e.confidence=100) as resolved_spatial_title_count,
    (select coalesce(jsonb_agg(jsonb_build_object(
        'inspire_id',e.source_ref,
        'polygon_area_sqm',e.details->>'polygon_area_sqm',
        'verified_at',e.verified_at
      ) order by e.verified_at desc),'[]'::jsonb)
      from public.lb_ownership_evidence e
      where e.site_id=s.id and e.evidence_type='inspire_spatial_point_match') as inspire_ids,
    (select coalesce(jsonb_agg(jsonb_build_object(
        'title_number',e.source_ref,
        'tenure',e.details->>'tenure',
        'property_postcode',e.details->>'property_postcode',
        'verified_at',e.verified_at
      ) order by e.verified_at desc),'[]'::jsonb)
      from public.lb_ownership_evidence e
      where e.site_id=s.id and e.evidence_type in ('title_relationship_confirmed','title_company_number_exact')) as ccod_titles
) x on true;

grant select on public.lb_ownership_workspace to anon,authenticated;

drop view if exists public.lb_ownership_gaps;
create view public.lb_ownership_gaps as
select
  s.id site_id,
  s.name,
  s.legacy_company_number,
  s.county,
  s.postcode,
  s.parcel_count,
  s.ownership_score,
  s.site_score,
  s.grid_score,
  s.solar_score,
  o.id opportunity_id,
  o.stage,
  o.priority_score,
  o.next_action,
  o.next_action_at,
  ow.ownership_status,
  ow.ccod_title_count,
  ow.inspire_point_hit_count,
  case
    when coalesce(s.ownership_score,0) < 60 then 'Confirm title/legal owner'
    when coalesce(s.ownership_score,0) < 85 then 'Strengthen owner/title relationship'
    when coalesce(s.ownership_score,0) < 100 and ow.inspire_point_hit_count=0 then 'Run HMLR INSPIRE spatial screen'
    when coalesce(s.ownership_score,0) < 100 then 'Resolve INSPIRE polygon ID to registered title'
    else 'Title + corporate owner + spatial relationship confirmed'
  end ownership_next_action
from public.lb_sites s
left join public.lb_opportunities o on o.site_id=s.id
left join public.lb_ownership_workspace ow on ow.site_id=s.id
where coalesce(s.ownership_score,0)<100
order by coalesce(o.priority_score,s.site_score,0) desc,s.parcel_count desc;

grant select on public.lb_ownership_gaps to anon,authenticated;
