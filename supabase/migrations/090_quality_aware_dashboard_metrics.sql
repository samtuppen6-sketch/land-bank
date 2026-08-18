create or replace view public.lb_sales_dashboard_metrics as
select count(*) AS universe,
       count(*) filter(where phone is not null and phone_trust_label in ('confirmed','trusted','probable') and stage in ('identified','researching','contact_ready','outreach_started')) AS callable_now,
       count(*) filter(where call_readiness_tier in ('A','B') and stage in ('identified','researching','contact_ready','outreach_started')) AS high_priority_callable,
       count(*) filter(where handover_status='ready') AS ready_to_handover,
       count(*) filter(where handover_status='handed_over') AS handed_over,
       count(*) filter(where next_action_at is not null and next_action_at<=now() and stage<>'closed_lost') AS actions_due,
       round(avg(site_potential_score),1) AS mean_site_potential,
       count(*) filter(where site_potential_completeness>=90) AS high_evidence_sites
from public.lb_call_readiness;

grant select on public.lb_sales_dashboard_metrics to anon,authenticated;