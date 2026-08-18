-- LandBank V2 temporary single-user browser access.
-- Keep the current PIN/anon architecture working, but remove destructive blanket privileges.

revoke all on table public.lb_import_snapshots from anon;

revoke delete, truncate, references, trigger on table
  public.lb_sites,
  public.lb_parcels,
  public.lb_organisations,
  public.lb_people,
  public.lb_organisation_people,
  public.lb_site_parties,
  public.lb_contact_points,
  public.lb_opportunities,
  public.lb_tasks,
  public.lb_site_assessments,
  public.lb_financial_scenarios,
  public.lb_enrichment_events,
  public.lb_qualifications,
  public.lb_stage_history
from anon;

revoke insert, update on table
  public.lb_sites,
  public.lb_parcels,
  public.lb_organisations,
  public.lb_people,
  public.lb_organisation_people,
  public.lb_site_parties,
  public.lb_contact_points,
  public.lb_site_assessments,
  public.lb_financial_scenarios,
  public.lb_enrichment_events
from anon;

grant select on table
  public.lb_sites,
  public.lb_parcels,
  public.lb_organisations,
  public.lb_people,
  public.lb_organisation_people,
  public.lb_site_parties,
  public.lb_contact_points,
  public.lb_opportunities,
  public.lb_tasks,
  public.lb_site_assessments,
  public.lb_financial_scenarios,
  public.lb_enrichment_events,
  public.lb_qualifications,
  public.lb_stage_history
 to anon;

grant insert, update on table public.lb_opportunities, public.lb_qualifications, public.lb_tasks, public.lb_stage_history to anon;

create or replace view public.lb_frontend_workspace
with (security_invoker = true)
as
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
  o.last_contacted_at,
  o.loss_reason,
  s.id as site_id,
  s.name as site_name,
  s.address_line,
  s.town,
  s.county,
  s.postcode,
  s.lat,
  s.lng,
  s.acreage_total,
  s.acreage_usable,
  s.parcel_count,
  s.potential_mwp,
  s.grid_score,
  s.planning_score,
  s.solar_score,
  s.land_score,
  s.environmental_score,
  s.ownership_score,
  s.overall_priority_score,
  org.id as organisation_id,
  org.name as organisation_name,
  org.company_number,
  org.website,
  org.domain,
  q.acres_available,
  q.usable_acres,
  q.contiguous,
  q.ownership_confirmed,
  q.occupier_or_tenant,
  q.current_land_use,
  q.access_notes,
  q.annual_consumption_kwh,
  q.annual_electricity_cost,
  q.current_tariff_p_per_kwh,
  q.mpan,
  q.half_hourly_data_available,
  q.peak_daytime_kw,
  q.three_phase_available,
  q.supply_notes,
  q.primary_objective,
  q.repayment_preference_pct,
  q.target_annual_income,
  q.decision_process,
  q.decision_makers,
  q.mortgage_or_charge,
  q.lender_name,
  q.existing_solar_or_renewables,
  q.lease_or_title_restrictions,
  q.site_visit_at,
  q.electricity_bills_received,
  q.half_hourly_data_received,
  q.letter_of_authority_received,
  q.indicative_terms_issued,
  q.heads_of_terms_issued,
  q.documents_outstanding,
  cp.phone,
  cp.phone_status,
  cp.email,
  cp.email_status,
  cp.website_contact,
  cp.contact_confidence
from public.lb_opportunities o
join public.lb_sites s on s.id=o.site_id
left join public.lb_organisations org on org.id=o.organisation_id
left join public.lb_qualifications q on q.opportunity_id=o.id
left join lateral (
  select
    max(value) filter (where type in ('phone','mobile') and is_primary) as phone,
    max(verification_status) filter (where type in ('phone','mobile') and is_primary) as phone_status,
    max(value) filter (where type='email' and is_primary) as email,
    max(verification_status) filter (where type='email' and is_primary) as email_status,
    max(value) filter (where type='website' and is_primary) as website_contact,
    max(confidence) as contact_confidence
  from public.lb_contact_points c
  where c.organisation_id=org.id
) cp on true;

grant select on public.lb_frontend_workspace to anon;

create or replace view public.lb_dashboard_metrics
with (security_invoker = true)
as
select
  count(*)::bigint as universe,
  count(*) filter (where stage='contact_ready')::bigint as contact_ready,
  count(*) filter (where stage not in ('identified','contact_ready','closed_lost'))::bigint as active_pipeline,
  coalesce(sum(parcel_count),0)::bigint as land_parcels,
  count(*) filter (where next_action_at is not null and next_action_at <= now())::bigint as actions_due,
  coalesce(sum(probability_weighted_value),0)::numeric as weighted_pipeline_value,
  coalesce(sum(potential_mwp),0)::numeric as potential_mwp
from public.lb_frontend_workspace;

grant select on public.lb_dashboard_metrics to anon;
