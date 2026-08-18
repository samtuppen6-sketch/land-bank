create or replace function public.lb_refresh_origination_scores()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sites integer:=0;v_opps integer:=0;
begin
  with base as (
    select s.id,
      case when s.grid_score is not null then s.grid_score when s.grid_proximity_score is not null then round(s.grid_proximity_score*.45,1) end grid_eff,
      least(100,round((20*sqrt(greatest(coalesce(s.parcel_count,0),0)))::numeric,1)) land_eff,
      s.planning_screen_score planning_eff,s.agricultural_score alc_eff,s.topography_score topo_eff,s.solar_score solar_eff,s.flood_score flood_eff,
      s.grid_score_confidence grid_conf,
      45::numeric land_conf,s.planning_score_confidence planning_conf,
      case when s.agricultural_score is null then null when coalesce(s.agricultural_grade,'') like 'Wales Predictive%' then 80 else 70 end::numeric alc_conf,
      s.topography_score_confidence topo_conf,85::numeric solar_conf,80::numeric flood_conf,
      s.ownership_score,s.parcel_count,s.grid_score,s.grid_proximity_score,s.planning_constraint_count,s.agricultural_grade,s.topography_p90_slope_deg
    from public.lb_sites s
  ), calc as (
    select b.*,
      (case when grid_eff is not null then 30 else 0 end + case when land_eff is not null then 20 else 0 end + case when planning_eff is not null then 15 else 0 end + case when alc_eff is not null then 10 else 0 end + case when topo_eff is not null then 10 else 0 end + case when solar_eff is not null then 10 else 0 end + case when flood_eff is not null then 5 else 0 end)::numeric available_weight,
      (coalesce(grid_eff*30,0)+coalesce(land_eff*20,0)+coalesce(planning_eff*15,0)+coalesce(alc_eff*10,0)+coalesce(topo_eff*10,0)+coalesce(solar_eff*10,0)+coalesce(flood_eff*5,0))::numeric weighted_sum,
      (coalesce(grid_conf*30,0)+coalesce(land_conf*20,0)+coalesce(planning_conf*15,0)+coalesce(alc_conf*10,0)+coalesce(topo_conf*10,0)+coalesce(solar_conf*10,0)+coalesce(flood_conf*5,0))/100.0 confidence_sum
    from base b
  )
  update public.lb_sites s set
    site_potential_score=case when c.available_weight>0 then round(c.weighted_sum/c.available_weight,1) end,
    site_potential_completeness=c.available_weight,
    site_potential_confidence=round(c.confidence_sum,1),
    site_potential_reasons=to_jsonb(array_remove(array[
      case when c.grid_score>=70 then 'Strong published grid capacity/headroom signal' when c.grid_score is null and c.grid_proximity_score>=70 then 'High-voltage grid infrastructure nearby (proxy)' end,
      case when coalesce(c.parcel_count,0)>=10 then 'Large source landholding signal' when coalesce(c.parcel_count,0)>=5 then 'Meaningful source landholding signal' end,
      case when c.solar_eff>=80 then 'Strong PVGIS solar yield' when c.solar_eff>=70 then 'Good PVGIS solar yield' end,
      case when c.flood_eff>=90 then 'Low flood-risk point screen' end,
      case when c.planning_eff>=90 and coalesce(c.planning_constraint_count,0)=0 then 'No major point planning/environment constraint identified' when c.planning_eff<70 then 'Material planning/environment point constraint flagged' end,
      case when c.alc_eff>=75 then 'Agricultural land quality comparatively favourable for solar screening' when c.alc_eff<=35 then 'Best/most versatile agricultural land risk flag' end,
      case when c.topo_eff>=80 then 'Favourable local terrain pre-screen' when c.topo_eff<55 then 'Challenging local terrain pre-screen' end,
      case when c.ownership_score>=85 then 'Strong HMLR-backed ownership relationship' end
    ]::text[],null)), updated_at=now()
  from calc c where s.id=c.id;
  get diagnostics v_sites=row_count;

  with contact as (
    select o.id,o.site_id,o.organisation_id,s.site_potential_score,s.ownership_score,o.stage,o.next_action_at,q.decision_makers,
      bool_or(cp.type in ('phone','mobile')) filter(where cp.type in ('phone','mobile')) has_phone,
      bool_or(cp.type in ('phone','mobile') and cp.trust_label in ('confirmed','trusted')) filter(where cp.type in ('phone','mobile')) good_phone,
      bool_or(cp.type='email') filter(where cp.type='email') has_email,
      bool_or(cp.type='email' and cp.trust_label in ('confirmed','trusted')) filter(where cp.type='email') good_email,
      bool_or(cp.type='website') filter(where cp.type='website') has_website
    from public.lb_opportunities o join public.lb_sites s on s.id=o.site_id
    left join public.lb_qualifications q on q.opportunity_id=o.id
    left join public.lb_best_contact_points cp on cp.organisation_id=o.organisation_id
    group by o.id,o.site_id,o.organisation_id,s.site_potential_score,s.ownership_score,o.stage,o.next_action_at,q.decision_makers
  ), scored as (
    select c.*,
      least(100,(case when good_phone then 45 when has_phone then 30 else 0 end)+(case when good_email then 20 when has_email then 12 else 0 end)+(case when nullif(trim(coalesce(decision_makers,'')),'') is not null then 20 else 0 end)+(case when has_website then 5 else 0 end)+(case when ownership_score>=85 then 10 else 0 end))::numeric contact_score
    from contact c
  ), final as (
    select *,round((coalesce(site_potential_score,0)*.65+contact_score*.25+coalesce(ownership_score,0)*.10)::numeric,1) call_score,
      round((coalesce(site_potential_score,0)*.75+(100-contact_score)*.25)::numeric,1) enrich_score
    from scored
  )
  update public.lb_opportunities o set
    contactability_score=f.contact_score,
    call_priority_score=f.call_score,
    enrichment_priority_score=f.enrich_score,
    why_calling=s.site_potential_reasons || to_jsonb(array_remove(array[
      case when f.good_phone then 'Trusted phone available' when f.has_phone then 'Phone available — provenance needs caution' end,
      case when nullif(trim(coalesce(f.decision_makers,'')),'') is not null then 'Decision-maker information available' end,
      case when f.good_email then 'Trusted email available for follow-up' when f.has_email then 'Email available for follow-up' end
    ]::text[],null)),
    updated_at=now()
  from final f join public.lb_sites s on s.id=f.site_id where o.id=f.id;
  get diagnostics v_opps=row_count;

  with ranked as (
    select id,row_number() over(order by call_priority_score desc nulls last,id) rn from public.lb_opportunities where stage not in ('lost','closed_lost')
  ) update public.lb_opportunities o set call_rank=r.rn from ranked r where o.id=r.id;

  return jsonb_build_object('sites_scored',v_sites,'opportunities_scored',v_opps);
end;$$;

create or replace view public.lb_sales_workspace as
select o.id AS opportunity_id,o.site_id,o.organisation_id,o.name,o.stage,o.probability,o.next_action,o.next_action_at,o.last_contacted_at,o.loss_reason,
       o.contactability_score,o.call_priority_score,o.enrichment_priority_score,o.call_rank,o.why_calling,o.handover_status,o.handover_score,o.handed_over_at,o.handover_recipient,o.handover_reference,
       s.name AS site_name,s.address_line,s.town,s.county,s.postcode,s.lat,s.lng,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.site_potential_confidence,s.site_potential_reasons,
       s.solar_score,s.flood_zone,s.flood_score,s.planning_screen_score,s.planning_score_confidence,s.planning_constraint_count,s.agricultural_grade,s.agricultural_score,s.topography_score,s.topography_median_slope_deg,s.topography_p90_slope_deg,s.topography_relief_m,s.ownership_score,
       ge.evidence_class AS grid_evidence_class,ge.grid_score,ge.grid_proximity_score,ge.grid_distance_km,ge.grid_node_name,ge.generation_headroom_mw,ge.evidence_note,
       org.name AS organisation_name,org.company_number,org.company_status,org.website,org.domain,
       COALESCE(NULLIF(btrim(q.decision_makers),''),ctrl.individual_controllers,ch.company_officers) AS decision_makers,
       q.authorised_decision_maker,q.interested_in_solar_income,q.acres_available,q.usable_acres,q.contiguous,q.occupier_or_tenant,q.current_land_use,q.large_vehicle_access,q.access_notes,q.existing_solar_or_renewables,q.mortgage_or_charge,q.lender_name,q.repayment_preference_pct,q.site_visit_interest,q.site_visit_at,q.consent_to_share,q.preferred_contact_time,q.handover_notes,q.qualified_at,
       ph.value AS phone,ph.verification_status AS phone_status,em.value AS email,em.verification_status AS email_status,web.value AS website_contact,
       ev.model_acres,ev.annual_kwh_per_kwp,ev.capacity_mwp_conservative,ev.capacity_mwp_base,ev.capacity_mwp_high_density,ev.annual_generation_mwh_base,ev.annual_gross_value_low,ev.annual_gross_value_base,ev.annual_gross_value_high,ev.gross_25y_constant_price_base,ev.export_price_low_gbp_mwh,ev.export_price_base_gbp_mwh,ev.export_price_high_gbp_mwh,ev.notes AS export_value_notes,
       ch.company_officers AS companies_house_officers,
       case when NULLIF(btrim(q.decision_makers),'') is not null then 'qualified' when ctrl.individual_controllers is not null then 'companies_house_psc' when ch.company_officers is not null then 'companies_house' end AS decision_maker_source,
       org.domain_source,org.domain_confidence,ctrl.company_controllers AS companies_house_controllers,
       ph.provider AS phone_provider,ph.source_url AS phone_source_url,ph.quality_score AS phone_quality_score,ph.trust_label AS phone_trust_label,ph.trust_reason AS phone_trust_reason,
       em.provider AS email_provider,em.source_url AS email_source_url,em.quality_score AS email_quality_score,em.trust_label AS email_trust_label,em.trust_reason AS email_trust_reason
from public.lb_opportunities o
join public.lb_sites s on s.id=o.site_id
left join public.lb_grid_evidence ge on ge.site_id=s.id
left join public.lb_organisations org on org.id=o.organisation_id
left join public.lb_qualifications q on q.opportunity_id=o.id
left join public.lb_sales_export_value ev on ev.opportunity_id=o.id
left join public.lb_company_controller_summary ctrl on ctrl.organisation_id=o.organisation_id
left join public.lb_company_officer_summary ch on ch.organisation_id=o.organisation_id
left join lateral (select * from public.lb_best_contact_points c where c.organisation_id=o.organisation_id and c.type in ('phone','mobile') order by c.quality_score desc limit 1) ph on true
left join lateral (select * from public.lb_best_contact_points c where c.organisation_id=o.organisation_id and c.type='email' order by c.quality_score desc limit 1) em on true
left join lateral (select * from public.lb_best_contact_points c where c.organisation_id=o.organisation_id and c.type='website' order by c.quality_score desc limit 1) web on true;

grant select on public.lb_sales_workspace to anon,authenticated;
select public.lb_refresh_origination_scores();