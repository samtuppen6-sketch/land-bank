create or replace view public.lb_company_officer_summary as
with ranked as (
  select
    op.organisation_id,
    p.full_name,
    op.role,
    op.is_primary,
    op.appointed_on,
    row_number() over (
      partition by op.organisation_id
      order by op.is_primary desc, op.appointed_on asc nulls last, p.full_name
    ) as rn
  from public.lb_organisation_people op
  join public.lb_people p on p.id=op.person_id
  where op.source='companies_house' and op.resigned_on is null
)
select
  organisation_id,
  string_agg(full_name || case when role is not null then ' ('||role||')' else '' end, ', ' order by is_primary desc, appointed_on asc nulls last, full_name) as company_officers,
  count(*)::integer as officer_count
from ranked
where rn<=4
group by organisation_id;

grant select on public.lb_company_officer_summary to anon,authenticated;

create or replace view public.lb_sales_workspace as
select
  o.id as opportunity_id,o.site_id,o.organisation_id,o.name,o.stage,o.probability,o.next_action,o.next_action_at,o.last_contacted_at,o.loss_reason,
  o.contactability_score,o.call_priority_score,o.enrichment_priority_score,o.call_rank,o.why_calling,o.handover_status,o.handover_score,o.handed_over_at,o.handover_recipient,o.handover_reference,
  s.name as site_name,s.address_line,s.town,s.county,s.postcode,s.lat,s.lng,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.site_potential_confidence,s.site_potential_reasons,
  s.solar_score,s.flood_zone,s.flood_score,s.planning_screen_score,s.planning_score_confidence,s.planning_constraint_count,s.agricultural_grade,s.agricultural_score,s.topography_score,s.topography_median_slope_deg,s.topography_p90_slope_deg,s.topography_relief_m,s.ownership_score,
  ge.evidence_class as grid_evidence_class,ge.grid_score,ge.grid_proximity_score,ge.grid_distance_km,ge.grid_node_name,ge.generation_headroom_mw,ge.evidence_note,
  org.name as organisation_name,org.company_number,org.company_status,org.website,org.domain,
  coalesce(nullif(btrim(q.decision_makers),''),ch.company_officers) as decision_makers,
  q.authorised_decision_maker,q.interested_in_solar_income,q.acres_available,q.usable_acres,q.contiguous,q.occupier_or_tenant,q.current_land_use,q.large_vehicle_access,q.access_notes,q.existing_solar_or_renewables,q.mortgage_or_charge,q.lender_name,q.repayment_preference_pct,q.site_visit_interest,q.site_visit_at,q.consent_to_share,q.preferred_contact_time,q.handover_notes,q.qualified_at,
  cp.phone,cp.phone_status,cp.email,cp.email_status,cp.website_contact,
  ev.model_acres,ev.annual_kwh_per_kwp,ev.capacity_mwp_conservative,ev.capacity_mwp_base,ev.capacity_mwp_high_density,ev.annual_generation_mwh_base,ev.annual_gross_value_low,ev.annual_gross_value_base,ev.annual_gross_value_high,ev.gross_25y_constant_price_base,ev.export_price_low_gbp_mwh,ev.export_price_base_gbp_mwh,ev.export_price_high_gbp_mwh,ev.notes as export_value_notes,
  ch.company_officers as companies_house_officers,
  case when nullif(btrim(q.decision_makers),'') is not null then 'qualified' when ch.company_officers is not null then 'companies_house' else null end as decision_maker_source
from public.lb_opportunities o
join public.lb_sites s on s.id=o.site_id
left join public.lb_grid_evidence ge on ge.site_id=s.id
left join public.lb_organisations org on org.id=o.organisation_id
left join public.lb_qualifications q on q.opportunity_id=o.id
left join public.lb_sales_export_value ev on ev.opportunity_id=o.id
left join public.lb_company_officer_summary ch on ch.organisation_id=o.organisation_id
left join lateral (
  select
    max(c.value) filter(where c.type=any(array['phone','mobile']) and not coalesce(c.do_not_contact,false) and c.is_primary) as phone,
    max(c.verification_status) filter(where c.type=any(array['phone','mobile']) and not coalesce(c.do_not_contact,false) and c.is_primary) as phone_status,
    max(c.value) filter(where c.type='email' and not coalesce(c.do_not_contact,false) and c.is_primary) as email,
    max(c.verification_status) filter(where c.type='email' and not coalesce(c.do_not_contact,false) and c.is_primary) as email_status,
    max(c.value) filter(where c.type='website' and c.is_primary) as website_contact
  from public.lb_contact_points c where c.organisation_id=o.organisation_id
) cp on true;

grant select on public.lb_sales_workspace to anon,authenticated;

create or replace view public.lb_top_100_to_call as
select
  o.call_rank,o.id as opportunity_id,o.name,o.stage,o.call_priority_score,o.contactability_score,o.enrichment_priority_score,o.why_calling,
  s.id as site_id,s.name as site_name,s.county,s.postcode,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.site_potential_confidence,s.solar_score,s.flood_score,s.planning_screen_score,s.agricultural_grade,s.agricultural_score,s.topography_score,s.ownership_score,
  ge.evidence_class as grid_evidence_class,ge.grid_score,ge.grid_proximity_score,ge.grid_distance_km,ge.grid_node_name,ge.generation_headroom_mw,ge.evidence_note,
  coalesce(nullif(btrim(q.decision_makers),''),ch.company_officers) as decision_makers,
  cp.phone,cp.phone_status,cp.email,cp.email_status,cp.website_contact,o.next_action,o.next_action_at
from public.lb_opportunities o
join public.lb_sites s on s.id=o.site_id
left join public.lb_grid_evidence ge on ge.site_id=s.id
left join public.lb_qualifications q on q.opportunity_id=o.id
left join public.lb_company_officer_summary ch on ch.organisation_id=o.organisation_id
left join lateral (
  select
    max(c.value) filter(where c.type=any(array['phone','mobile']) and not coalesce(c.do_not_contact,false)) as phone,
    max(c.verification_status) filter(where c.type=any(array['phone','mobile']) and not coalesce(c.do_not_contact,false)) as phone_status,
    max(c.value) filter(where c.type='email' and not coalesce(c.do_not_contact,false)) as email,
    max(c.verification_status) filter(where c.type='email' and not coalesce(c.do_not_contact,false)) as email_status,
    max(c.value) filter(where c.type='website') as website_contact
  from public.lb_contact_points c where c.organisation_id=o.organisation_id
) cp on true
where o.stage=any(array['identified','researching','contact_ready','outreach_started']) and cp.phone is not null
order by o.call_priority_score desc nulls last
limit 100;

grant select on public.lb_top_100_to_call to anon,authenticated;

create or replace view public.lb_enrichment_queue as
select
  o.id as opportunity_id,o.name,o.stage,o.enrichment_priority_score,o.call_priority_score,o.contactability_score,o.why_calling,
  s.id as site_id,s.county,s.postcode,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.ownership_score,
  coalesce(nullif(btrim(q.decision_makers),''),ch.company_officers) as decision_makers
from public.lb_opportunities o
join public.lb_sites s on s.id=o.site_id
left join public.lb_qualifications q on q.opportunity_id=o.id
left join public.lb_company_officer_summary ch on ch.organisation_id=o.organisation_id
where o.stage=any(array['identified','researching','contact_ready']) and o.contactability_score<70
order by o.enrichment_priority_score desc nulls last;

grant select on public.lb_enrichment_queue to anon,authenticated;
