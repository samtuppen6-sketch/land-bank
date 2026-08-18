create or replace function public.lb_refresh_contact_review_queue()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  update public.lb_contact_review_queue q
     set status='approved',reviewer_notes='Auto-approved: independently cross-confirmed by trusted source',reviewed_at=now(),updated_at=now()
   where q.status='pending'
     and exists(
       select 1 from public.lb_contact_points cp
       join public.lb_contact_points x on x.organisation_id=cp.organisation_id and x.type=cp.type and x.id<>cp.id
       where cp.id=q.contact_point_id
         and lower(regexp_replace(x.value,'[^a-zA-Z0-9@.+]','','g'))=lower(regexp_replace(cp.value,'[^a-zA-Z0-9@.+]','','g'))
         and x.provider in ('website_crawl','hunter','openstreetmap','google_places')
         and coalesce(x.confidence,0)>=80
         and x.verification_status in ('probable','verified','catch_all')
     );

  with candidates as (
    select cp.id contact_point_id,cp.organisation_id,
      case when cp.provider ilike 'Google Places —%' then 'Legacy Google Places contact is not independently cross-checked'
           when coalesce(cp.confidence,0)<70 then 'Low-confidence contact'
           when coalesce(cp.verification_status,'unknown')='unknown' then 'Unverified contact'
           when cp.source_url is null and cp.provider not in ('website_crawl','hunter','openstreetmap','google_places') then 'Contact has weak source provenance'
           else 'Contact requires provenance review' end reason,
      case when cp.provider ilike 'Google Places —%' and cp.verification_status='unknown' then 85
           when cp.provider ilike 'Google Places —%' then 65
           when coalesce(cp.confidence,0)<50 then 90
           when coalesce(cp.confidence,0)<70 then 75
           when coalesce(cp.verification_status,'unknown')='unknown' then 70 else 55 end::numeric risk_score
    from public.lb_contact_points cp
    where coalesce(cp.do_not_contact,false)=false
      and (cp.provider ilike 'Google Places —%' or coalesce(cp.confidence,0)<70 or coalesce(cp.verification_status,'unknown')='unknown' or (cp.source_url is null and cp.provider not in ('website_crawl','hunter','openstreetmap','google_places')))
      and not exists(select 1 from public.lb_contact_points x where x.organisation_id=cp.organisation_id and x.type=cp.type and x.id<>cp.id and lower(regexp_replace(x.value,'[^a-zA-Z0-9@.+]','','g'))=lower(regexp_replace(cp.value,'[^a-zA-Z0-9@.+]','','g')) and x.provider in ('website_crawl','hunter','openstreetmap','google_places') and coalesce(x.confidence,0)>=80 and x.verification_status in ('probable','verified','catch_all'))
  ), ins as (
    insert into public.lb_contact_review_queue(contact_point_id,organisation_id,reason,risk_score,updated_at)
    select contact_point_id,organisation_id,reason,risk_score,now() from candidates
    on conflict(contact_point_id) do update set reason=excluded.reason,risk_score=excluded.risk_score,updated_at=now() returning id
  ) select count(*) into v_count from ins;
  return v_count;
end;$$;

create or replace view public.lb_priority_contact_review with (security_invoker=true) as
select r.id review_id,r.status review_status,r.risk_score,r.reason,r.reviewer_notes,
       cp.id contact_point_id,cp.type,cp.value,cp.provider,cp.verification_status,cp.confidence,cp.source_url,
       o.id opportunity_id,o.name opportunity_name,o.call_rank,o.call_priority_score,o.contactability_score,
       s.name site_name,s.town,s.county,s.postcode,org.name organisation_name
from public.lb_contact_review_queue r
join public.lb_contact_points cp on cp.id=r.contact_point_id
join public.lb_organisations org on org.id=r.organisation_id
join public.lb_opportunities o on o.organisation_id=org.id
join public.lb_sites s on s.id=o.site_id
where r.status='pending'
order by (case when o.call_rank<=200 then 0 else 1 end),o.call_rank nulls last,r.risk_score desc;
grant select on public.lb_priority_contact_review to anon,authenticated;

create or replace function public.lb_refresh_contact_enrichment_queues()
returns jsonb language plpgsql security definer set search_path=public as $$
declare vr integer;vg jsonb;begin
  vr:=public.lb_refresh_contact_review_queue();
  vg:=public.lb_refresh_paid_gap_targets(1000);
  return jsonb_build_object('review_rows_refreshed',vr,'gap_jobs',vg);
end;$$;
revoke all on function public.lb_refresh_contact_enrichment_queues() from public,anon,authenticated;
grant execute on function public.lb_refresh_contact_enrichment_queues() to service_role;

do $$ begin perform cron.unschedule('landbank-contact-enrichment-refresh'); exception when others then null; end $$;
select cron.schedule('landbank-contact-enrichment-refresh','*/10 * * * *',$$select public.lb_refresh_contact_enrichment_queues();$$);
select public.lb_refresh_contact_enrichment_queues();
