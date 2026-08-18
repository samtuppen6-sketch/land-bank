create or replace view public.lb_top_100_to_call as
select o.call_rank,o.id opportunity_id,o.name,o.stage,o.call_priority_score,o.contactability_score,o.enrichment_priority_score,o.why_calling,
       s.id site_id,s.name site_name,s.county,s.postcode,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.site_potential_confidence,
       s.solar_score,s.flood_score,s.planning_screen_score,s.agricultural_grade,s.agricultural_score,s.topography_score,s.ownership_score,
       ge.evidence_class grid_evidence_class,ge.grid_score,ge.grid_proximity_score,ge.grid_distance_km,ge.grid_node_name,ge.generation_headroom_mw,ge.evidence_note,
       q.decision_makers,cp.phone,cp.phone_status,cp.email,cp.email_status,cp.website_contact,o.next_action,o.next_action_at
from public.lb_opportunities o join public.lb_sites s on s.id=o.site_id
left join public.lb_grid_evidence ge on ge.site_id=s.id left join public.lb_qualifications q on q.opportunity_id=o.id
left join lateral (
  select max(c.value) filter(where c.type in ('phone','mobile') and not coalesce(c.do_not_contact,false)) phone,
         max(c.verification_status) filter(where c.type in ('phone','mobile') and not coalesce(c.do_not_contact,false)) phone_status,
         max(c.value) filter(where c.type='email' and not coalesce(c.do_not_contact,false)) email,
         max(c.verification_status) filter(where c.type='email' and not coalesce(c.do_not_contact,false)) email_status,
         max(c.value) filter(where c.type='website') website_contact
  from public.lb_contact_points c where c.organisation_id=o.organisation_id
) cp on true
where o.stage in ('identified','researching','contact_ready','outreach_started') and cp.phone is not null
order by o.call_priority_score desc nulls last limit 100;

create or replace view public.lb_enrichment_queue as
select o.id opportunity_id,o.name,o.stage,o.enrichment_priority_score,o.call_priority_score,o.contactability_score,o.why_calling,
       s.id site_id,s.county,s.postcode,s.parcel_count,s.site_potential_score,s.site_potential_completeness,s.ownership_score,q.decision_makers
from public.lb_opportunities o join public.lb_sites s on s.id=o.site_id
left join public.lb_qualifications q on q.opportunity_id=o.id
where o.stage in ('identified','researching','contact_ready') and o.contactability_score<70
order by o.enrichment_priority_score desc nulls last;

grant select on public.lb_top_100_to_call,public.lb_enrichment_queue to anon,authenticated;
select public.lb_refresh_origination_scores();
select cron.unschedule(jobid) from cron.job where jobname='landbank-origination-score-refresh';
select cron.schedule('landbank-origination-score-refresh','*/5 * * * *','select public.lb_refresh_origination_scores();');