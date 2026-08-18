alter table public.lb_contact_gap_jobs drop constraint if exists lb_contact_gap_jobs_provider_check;
alter table public.lb_contact_gap_jobs add constraint lb_contact_gap_jobs_provider_check check (provider = any(array['foursquare_os'::text,'google_places'::text,'hunter'::text]));

update public.lb_contact_gap_jobs
set status='blocked', last_error='Waiting for Foursquare OS free-source stage', updated_at=now()
where provider in ('google_places','hunter') and status='queued';

create or replace function public.lb_refresh_paid_gap_targets(p_limit integer default 1000)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare vf integer:=0; vg integer:=0; vh integer:=0;begin
  perform public.lb_refresh_web_crawl_targets_from_domains(p_limit);

  with base as (
    select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,org.domain,org.website,
      exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and cp.type in ('phone','mobile') and not coalesce(cp.do_not_contact,false) and cp.verification_status in ('probable','verified') and coalesce(cp.confidence,0)>=80) good_phone,
      exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and cp.type='email' and not coalesce(cp.do_not_contact,false) and cp.verification_status in ('probable','verified','catch_all') and coalesce(cp.confidence,0)>=80) good_email,
      exists(select 1 from public.lb_osm_contact_jobs j where j.opportunity_id=e.opportunity_id and j.status in ('completed','no_match','failed')) osm_done,
      not exists(select 1 from public.lb_web_crawl_jobs w where w.organisation_id=o.organisation_id and w.status in ('queued','processing')) web_done
    from public.lb_enrichment_queue e
    join public.lb_opportunities o on o.id=e.opportunity_id
    join public.lb_organisations org on org.id=o.organisation_id
  ), f as (
    insert into public.lb_contact_gap_jobs(opportunity_id,site_id,organisation_id,provider,priority_score,status,next_attempt_at,updated_at)
    select opportunity_id,site_id,organisation_id,'foursquare_os',enrichment_priority_score,'queued',now(),now()
    from base
    where osm_done and web_done and (not good_phone or not good_email)
    order by enrichment_priority_score desc nulls last limit greatest(1,least(2000,p_limit))
    on conflict(opportunity_id,provider) do nothing returning id
  ) select count(*) into vf from f;

  update public.lb_contact_gap_jobs g
  set status='queued',last_error=null,next_attempt_at=now(),updated_at=now()
  where g.provider in ('google_places','hunter') and g.status='blocked'
    and exists(select 1 from public.lb_contact_gap_jobs f where f.opportunity_id=g.opportunity_id and f.provider='foursquare_os' and f.status in ('completed','no_contact','failed'));

  with base as (
    select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,
      exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and cp.type in ('phone','mobile') and not coalesce(cp.do_not_contact,false) and cp.verification_status in ('probable','verified') and coalesce(cp.confidence,0)>=80) good_phone,
      exists(select 1 from public.lb_contact_gap_jobs f where f.opportunity_id=e.opportunity_id and f.provider='foursquare_os' and f.status in ('completed','no_contact','failed')) fsq_done
    from public.lb_enrichment_queue e
    join public.lb_opportunities o on o.id=e.opportunity_id
  ), g as (
    insert into public.lb_contact_gap_jobs(opportunity_id,site_id,organisation_id,provider,priority_score,status,next_attempt_at,updated_at)
    select opportunity_id,site_id,organisation_id,'google_places',enrichment_priority_score,'queued',now(),now()
    from base where not good_phone and fsq_done
    order by enrichment_priority_score desc nulls last limit greatest(1,least(2000,p_limit))
    on conflict(opportunity_id,provider) do nothing returning id
  ) select count(*) into vg from g;

  with base as (
    select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,org.domain,org.website,org.domain_confidence,org.domain_source,
      exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and cp.type='email' and not coalesce(cp.do_not_contact,false) and cp.verification_status in ('probable','verified','catch_all') and coalesce(cp.confidence,0)>=80) good_email,
      exists(select 1 from public.lb_contact_gap_jobs f where f.opportunity_id=e.opportunity_id and f.provider='foursquare_os' and f.status in ('completed','no_contact','failed')) fsq_done
    from public.lb_enrichment_queue e
    join public.lb_opportunities o on o.id=e.opportunity_id
    join public.lb_organisations org on org.id=o.organisation_id
  ), h as (
    insert into public.lb_contact_gap_jobs(opportunity_id,site_id,organisation_id,provider,priority_score,status,next_attempt_at,updated_at)
    select opportunity_id,site_id,organisation_id,'hunter',enrichment_priority_score,'queued',now(),now()
    from base
    where not good_email and fsq_done and domain is not null
      and (coalesce(domain_confidence,0)>=80 or domain_source in ('website_crawl','openstreetmap','foursquare_os','google_places','manual','trusted_import') or website is not null)
    order by enrichment_priority_score desc nulls last limit greatest(1,least(2000,p_limit))
    on conflict(opportunity_id,provider) do nothing returning id
  ) select count(*) into vh from h;

  return jsonb_build_object('foursquare_os_added',vf,'google_places_added',vg,'hunter_added',vh);
end;$$;

select public.lb_refresh_paid_gap_targets(1000);
