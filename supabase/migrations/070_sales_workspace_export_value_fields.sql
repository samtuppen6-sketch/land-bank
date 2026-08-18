-- Append acreage-driven export-only value scenarios to the lean sales workspace.
create or replace view public.lb_sales_workspace as
select
  o.id as opportunity_id,o.site_id,o.organisation_id,o.name,o.stage,o.probability,o.next_action,o.next_action_at,o.last_contacted_at,o.loss_reason,
  o.contactability_score,o.call_priority_score,o.enrichment_priority_score,o.call_rank,o.why_calling,o.handover_status,o.handover_score,o.handed_over_at,o.handover_recipient,o.handover_reference,
  s.name as site_name,s.address_line,s.town,s.county,s.postcode,s.lat,s.lng,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.site_potential_confidence,s.site_potential_reasons,
  s.solar_score,s.flood_zone,s.flood_score,s.planning_screen_score,s.planning_score_confidence,s.planning_constraint_count,s.agricultural_grade,s.agricultural_score,s.topography_score,s.topography_median_slope_deg,s.topography_p90_slope_deg,s.topography_relief_m,s.ownership_score,
  ge.evidence_class as grid_evidence_class,ge.grid_score,ge.grid_proximity_score,ge.grid_distance_km,ge.grid_node_name,ge.generation_headroom_mw,ge.evidence_note,
  org.name as organisation_name,org.company_number,org.company_status,org.website,org.domain,
  q.decision_makers,q.authorised_decision_maker,q.interested_in_solar_income,q.acres_available,q.usable_acres,q.contiguous,q.occupier_or_tenant,q.current_land_use,q.large_vehicle_access,q.access_notes,q.existing_solar_or_renewables,q.mortgage_or_charge,q.lender_name,q.repayment_preference_pct,q.site_visit_interest,q.site_visit_at,q.consent_to_share,q.preferred_contact_time,q.handover_notes,q.qualified_at,
  cp.phone,cp.phone_status,cp.email,cp.email_status,cp.website_contact,
  ev.model_acres,ev.annual_kwh_per_kwp,ev.capacity_mwp_conservative,ev.capacity_mwp_base,ev.capacity_mwp_high_density,ev.annual_generation_mwh_base,
  ev.annual_gross_value_low,ev.annual_gross_value_base,ev.annual_gross_value_high,ev.gross_25y_constant_price_base,
  ev.export_price_low_gbp_mwh,ev.export_price_base_gbp_mwh,ev.export_price_high_gbp_mwh,ev.notes as export_value_notes
from public.lb_opportunities o
join public.lb_sites s on s.id=o.site_id
left join public.lb_grid_evidence ge on ge.site_id=s.id
left join public.lb_organisations org on org.id=o.organisation_id
left join public.lb_qualifications q on q.opportunity_id=o.id
left join public.lb_sales_export_value ev on ev.opportunity_id=o.id
left join lateral (
  select
    max(c.value) filter(where c.type in ('phone','mobile') and not coalesce(c.do_not_contact,false) and c.is_primary) as phone,
    max(c.verification_status) filter(where c.type in ('phone','mobile') and not coalesce(c.do_not_contact,false) and c.is_primary) as phone_status,
    max(c.value) filter(where c.type='email' and not coalesce(c.do_not_contact,false) and c.is_primary) as email,
    max(c.verification_status) filter(where c.type='email' and not coalesce(c.do_not_contact,false) and c.is_primary) as email_status,
    max(c.value) filter(where c.type='website' and c.is_primary) as website_contact
  from public.lb_contact_points c where c.organisation_id=o.organisation_id
) cp on true;
grant select on public.lb_sales_workspace to anon,authenticated;