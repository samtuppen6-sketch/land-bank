create or replace view public.lb_domain_discovery_queue with (security_invoker=false) as
select
  op.id as opportunity_id,
  op.site_id,
  op.organisation_id,
  op.call_priority_score,
  org.name as organisation_name,
  org.domain,
  org.domain_source,
  org.domain_confidence,
  org.domain_checked_at,
  s.postcode,
  s.town,
  s.county,
  org.company_number,
  org.registered_address
from public.lb_opportunities op
join public.lb_organisations org on org.id=op.organisation_id
join public.lb_sites s on s.id=op.site_id
where org.domain is null
  and coalesce(op.call_priority_score,0)>=0;
revoke all on public.lb_domain_discovery_queue from anon,authenticated;
