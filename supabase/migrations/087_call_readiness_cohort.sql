create or replace view public.lb_call_readiness with (security_invoker=false) as
select w.*,
  least(100,
    (case w.phone_trust_label when 'confirmed' then 35 when 'trusted' then 35 when 'probable' then 25 else 0 end)
    + (case when nullif(btrim(w.decision_makers),'') is not null then 20 else 0 end)
    + (case when w.site_potential_score>=80 then 20 when w.site_potential_score>=70 then 17 when w.site_potential_score>=65 then 12 else 5 end)
    + (case when w.grid_score is not null then 10 when w.grid_proximity_score is not null then 5 else 0 end)
    + (case when w.site_potential_completeness>=90 then 10 when w.site_potential_completeness>=75 then 7 else 3 end)
    + (case when w.ownership_score>=85 then 5 else 0 end)
  )::numeric as call_readiness_score,
  case
    when w.phone_trust_label in ('confirmed','trusted') and nullif(btrim(w.decision_makers),'') is not null and w.site_potential_score>=70 and w.site_potential_completeness>=75 then 'A'
    when w.phone_trust_label in ('confirmed','trusted','probable') and nullif(btrim(w.decision_makers),'') is not null and w.site_potential_score>=65 then 'B'
    else 'HOLD'
  end as call_readiness_tier
from public.lb_sales_workspace w;

grant select on public.lb_call_readiness to anon,authenticated;

create or replace view public.lb_top_100_to_call as
with eligible as (
  select r.*,
         row_number() over(
           partition by regexp_replace(coalesce(r.phone,''),'[^0-9]','','g')
           order by case r.call_readiness_tier when 'A' then 1 else 2 end,
                    r.call_priority_score desc nulls last,
                    r.call_readiness_score desc,
                    r.opportunity_id
         ) as phone_destination_rank
  from public.lb_call_readiness r
  where r.stage in ('identified','researching','contact_ready','outreach_started')
    and r.phone is not null
    and r.phone_trust_label in ('confirmed','trusted','probable')
    and r.call_readiness_tier in ('A','B')
)
select call_rank,opportunity_id,name,stage,call_priority_score,contactability_score,enrichment_priority_score,why_calling,
       site_id,site_name,county,postcode,parcel_count,site_potential_score,site_potential_completeness,site_potential_confidence,
       solar_score,flood_score,planning_screen_score,agricultural_grade,agricultural_score,topography_score,ownership_score,
       grid_evidence_class,grid_score,grid_proximity_score,grid_distance_km,grid_node_name,generation_headroom_mw,evidence_note,
       decision_makers,phone,phone_status,email,email_status,website_contact,next_action,next_action_at,companies_house_controllers,
       phone_provider,phone_source_url,phone_quality_score,phone_trust_label,phone_trust_reason,email_provider,email_quality_score,email_trust_label,
       call_readiness_score,call_readiness_tier
from eligible
where phone_destination_rank=1
order by case call_readiness_tier when 'A' then 1 else 2 end,call_priority_score desc nulls last,call_readiness_score desc
limit 100;

grant select on public.lb_top_100_to_call to anon,authenticated;