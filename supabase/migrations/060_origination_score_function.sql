create or replace function public.lb_refresh_origination_scores()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sites integer:=0;v_opps integer:=0;
begin
  with base as (
    select s.id,
      case when s.grid_score is not null then s.grid_score when s.grid_proximity_score is not null then round(s.grid_proximity_score*.45,1) end grid_eff,
      least(100,round((20*sqrt(greatest(coalesce(s.parcel_count,0),0)))::numeric,1)) land_eff,
      s.planning_screen_score planning_eff,s.agricultural_score alc_eff,s.topography_score topo_eff,s.solar_score solar_eff,s.flood_score flood_eff,
      s.grid_score_confidence grid_conf,45::numeric land_conf,s.planning_score_confidence planning_conf,
      case when s.agricultural_score is null then null when coalesce(s.agricultural_grade,'') like 'Wales Predictive%' then 80 else 70 end::numeric alc_conf,
      s.topography_score_confidence topo_conf,85::numeric solar_conf,80::numeric flood_conf,
      s.ownership_score,s.parcel_count,s.grid_score,s.grid_proximity_score,s.planning_constraint_count
    from public.lb_sites s
  ), calc as (
    select b.*,
      (case when grid_eff is not null then 30 else 0 end+case when land_eff is not null then 20 else 0 end+case when planning_eff is not null then 15 else 0 end+case when alc_eff is not null then 10 else 0 end+case when topo_eff is not null then 10 else 0 end+case when solar_eff is not null then 10 else 0 end+case when flood_eff is not null then 5 else 0 end)::numeric available_weight,
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
    ]::text[],null)),updated_at=now()
  from calc c where s.id=c.id;
  get diagnostics v_sites=row_count;

  with contact as (
    select o.id,o.site_id,o.organisation_id,s.site_potential_score,s.ownership_score,q.decision_makers,
      bool_or(cp.type in ('phone','mobile') and not coalesce(cp.do_not_contact,false)) filter(where cp.type in ('phone','mobile')) has_phone,
      bool_or(cp.type in ('phone','mobile') and cp.verification_status in ('probable','verified') and not coalesce(cp.do_not_contact,false)) filter(where cp.type in ('phone','mobile')) good_phone,
      bool_or(cp.type='email' and not coalesce(cp.do_not_contact,false)) filter(where cp.type='email') has_email,
      bool_or(cp.type='email' and cp.verification_status in ('probable','verified') and not coalesce(cp.do_not_contact,false)) filter(where cp.type='email') good_email,
      bool_or(cp.type='website') filter(where cp.type='website') has_website
    from public.lb_opportunities o join public.lb_sites s on s.id=o.site_id
    left join public.lb_qualifications q on q.opportunity_id=o.id left join public.lb_contact_points cp on cp.organisation_id=o.organisation_id
    group by o.id,o.site_id,o.organisation_id,s.site_potential_score,s.ownership_score,q.decision_makers
  ), scored as (
    select c.*,least(100,(case when has_phone then 35 else 0 end)+(case when good_phone then 10 else 0 end)+(case when has_email then 15 else 0 end)+(case when good_email then 5 else 0 end)+(case when nullif(trim(coalesce(decision_makers,'')),'') is not null then 20 else 0 end)+(case when has_website then 5 else 0 end)+(case when ownership_score>=85 then 10 else 0 end))::numeric contact_score from contact c
  ), final as (
    select *,round((coalesce(site_potential_score,0)*.65+contact_score*.25+coalesce(ownership_score,0)*.10)::numeric,1) call_score,round((coalesce(site_potential_score,0)*.75+(100-contact_score)*.25)::numeric,1) enrich_score from scored
  )
  update public.lb_opportunities o set contactability_score=f.contact_score,call_priority_score=f.call_score,enrichment_priority_score=f.enrich_score,
    why_calling=s.site_potential_reasons||to_jsonb(array_remove(array[case when f.has_phone then 'Phone available' end,case when nullif(trim(coalesce(f.decision_makers,'')),'') is not null then 'Decision-maker information available' end,case when f.has_email then 'Email available for follow-up' end]::text[],null)),updated_at=now()
  from final f join public.lb_sites s on s.id=f.site_id where o.id=f.id;
  get diagnostics v_opps=row_count;

  with ranked as (select id,row_number() over(order by call_priority_score desc nulls last,id) rn from public.lb_opportunities where stage<>'closed_lost')
  update public.lb_opportunities o set call_rank=r.rn from ranked r where o.id=r.id;
  return jsonb_build_object('sites_scored',v_sites,'opportunities_scored',v_opps);
end;$$;

revoke all on function public.lb_refresh_origination_scores() from public,anon,authenticated;
grant execute on function public.lb_refresh_origination_scores() to service_role;