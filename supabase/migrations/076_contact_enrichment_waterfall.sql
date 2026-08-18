-- LandBank V2 contact enrichment waterfall:
-- Companies House -> trusted website -> OpenStreetMap -> gap-only Google Places -> Hunter -> human review.

create table if not exists public.lb_osm_contact_jobs (
  id uuid primary key default gen_random_uuid(), opportunity_id uuid not null references public.lb_opportunities(id) on delete cascade,
  site_id uuid not null references public.lb_sites(id) on delete cascade, organisation_id uuid not null references public.lb_organisations(id) on delete cascade,
  priority_score numeric, status text not null default 'queued' check(status in ('queued','processing','completed','failed','no_match')),
  attempts integer not null default 0, next_attempt_at timestamptz not null default now(), locked_at timestamptz, completed_at timestamptz,
  last_error text,last_result jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(opportunity_id)
);
create index if not exists lb_osm_contact_jobs_status_idx on public.lb_osm_contact_jobs(status,next_attempt_at,priority_score desc);
revoke all on public.lb_osm_contact_jobs from anon,authenticated;

create or replace function public.lb_refresh_osm_contact_targets(p_limit integer default 1000)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  with targets as (
    select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,row_number() over(order by e.enrichment_priority_score desc nulls last,e.opportunity_id) rn
    from public.lb_enrichment_queue e join public.lb_opportunities o on o.id=e.opportunity_id join public.lb_sites s on s.id=e.site_id
    where s.lat is not null and s.lng is not null and o.organisation_id is not null
      and not exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and coalesce(cp.do_not_contact,false)=false and cp.type in ('phone','mobile','email') and coalesce(cp.confidence,0)>=80)
  ), ins as (
    insert into public.lb_osm_contact_jobs(opportunity_id,site_id,organisation_id,priority_score,status,next_attempt_at,updated_at)
    select opportunity_id,site_id,organisation_id,enrichment_priority_score,'queued',now(),now() from targets where rn<=greatest(1,least(2000,p_limit))
    on conflict(opportunity_id) do update set priority_score=excluded.priority_score,updated_at=now() returning id
  ) select count(*) into v_count from ins; return v_count;end;$$;
revoke all on function public.lb_refresh_osm_contact_targets(integer) from public,anon,authenticated;
grant execute on function public.lb_refresh_osm_contact_targets(integer) to service_role;

create or replace view public.lb_osm_contact_progress with (security_invoker=true) as
select count(*) total_targets,count(*) filter(where status='queued') queued,count(*) filter(where status='processing') processing,
count(*) filter(where status='completed') completed,count(*) filter(where status='no_match') no_match,count(*) filter(where status='failed') failed from public.lb_osm_contact_jobs;
grant select on public.lb_osm_contact_progress to anon,authenticated;

create or replace function public.lb_kick_osm_contact_batch() returns bigint language plpgsql security definer set search_path=public,net,cron as $$
declare v_request_id bigint;v_remaining integer;v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhkb3FjbHJ3ZGR1bmNqYXh0aXhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwMjkyNjMsImV4cCI6MjA5NjYwNTI2M30.vLCzN7-eNJh32tvy0zySDGX5bp6X1v9WlST59BSmIkk';begin
  update public.lb_osm_contact_jobs set status='queued',locked_at=null,updated_at=now(),last_error=coalesce(last_error,'')||case when coalesce(last_error,'')='' then '' else ' | ' end||'stale processing lease reset' where status='processing' and locked_at<now()-interval '20 minutes';
  select count(*) into v_remaining from public.lb_osm_contact_jobs where status in ('queued','processing');
  if v_remaining=0 then begin perform cron.unschedule('landbank-osm-contact-enrichment');exception when others then null;end;return null;end if;
  select net.http_post(url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/process-osm-contact-batch',body:=jsonb_build_object('batch_size',3),params:='{}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer '||v_anon),timeout_milliseconds:=120000) into v_request_id;return v_request_id;end;$$;
revoke all on function public.lb_kick_osm_contact_batch() from public,anon,authenticated;grant execute on function public.lb_kick_osm_contact_batch() to service_role;
do $$ begin perform cron.unschedule('landbank-osm-contact-enrichment');exception when others then null;end $$;
select cron.schedule('landbank-osm-contact-enrichment','* * * * *',$$select public.lb_kick_osm_contact_batch();$$);
select public.lb_refresh_osm_contact_targets(1000);

create table if not exists public.lb_contact_review_queue (
 id uuid primary key default gen_random_uuid(),contact_point_id uuid not null unique references public.lb_contact_points(id) on delete cascade,
 organisation_id uuid not null references public.lb_organisations(id) on delete cascade,reason text not null,risk_score numeric not null default 50,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),reviewer_notes text,reviewed_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists lb_contact_review_queue_status_idx on public.lb_contact_review_queue(status,risk_score desc);
revoke all on public.lb_contact_review_queue from anon,authenticated;
create or replace function public.lb_refresh_contact_review_queue() returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
 with candidates as (
  select cp.id contact_point_id,cp.organisation_id,
   case when cp.provider ilike 'Google Places —%' then 'Legacy Google Places contact is not independently cross-checked' when coalesce(cp.confidence,0)<70 then 'Low-confidence contact' when coalesce(cp.verification_status,'unknown')='unknown' then 'Unverified contact' when cp.source_url is null and cp.provider not in ('website_crawl','hunter','openstreetmap','google_places') then 'Contact has weak source provenance' else 'Contact requires provenance review' end reason,
   case when cp.provider ilike 'Google Places —%' and cp.verification_status='unknown' then 85 when cp.provider ilike 'Google Places —%' then 65 when coalesce(cp.confidence,0)<50 then 90 when coalesce(cp.confidence,0)<70 then 75 when coalesce(cp.verification_status,'unknown')='unknown' then 70 else 55 end::numeric risk_score
  from public.lb_contact_points cp where coalesce(cp.do_not_contact,false)=false and (cp.provider ilike 'Google Places —%' or coalesce(cp.confidence,0)<70 or coalesce(cp.verification_status,'unknown')='unknown' or (cp.source_url is null and cp.provider not in ('website_crawl','hunter','openstreetmap','google_places')))
   and not exists(select 1 from public.lb_contact_points x where x.organisation_id=cp.organisation_id and x.type=cp.type and lower(regexp_replace(x.value,'[^a-zA-Z0-9@.+]','','g'))=lower(regexp_replace(cp.value,'[^a-zA-Z0-9@.+]','','g')) and x.id<>cp.id and x.provider in ('website_crawl','hunter','openstreetmap','google_places') and coalesce(x.confidence,0)>=80 and x.verification_status in ('probable','verified','catch_all'))
 ),ins as (insert into public.lb_contact_review_queue(contact_point_id,organisation_id,reason,risk_score,updated_at) select contact_point_id,organisation_id,reason,risk_score,now() from candidates on conflict(contact_point_id) do update set reason=excluded.reason,risk_score=excluded.risk_score,updated_at=now() returning id)
 select count(*) into v_count from ins;return v_count;end;$$;
revoke all on function public.lb_refresh_contact_review_queue() from public,anon,authenticated;grant execute on function public.lb_refresh_contact_review_queue() to service_role;
create or replace view public.lb_contact_review_progress with (security_invoker=true) as select count(*) total,count(*) filter(where status='pending') pending,count(*) filter(where status='approved') approved,count(*) filter(where status='rejected') rejected,round(avg(risk_score),1) mean_risk from public.lb_contact_review_queue;
grant select on public.lb_contact_review_progress to anon,authenticated;

create table if not exists public.lb_contact_gap_jobs (
 id uuid primary key default gen_random_uuid(),opportunity_id uuid not null references public.lb_opportunities(id) on delete cascade,site_id uuid not null references public.lb_sites(id) on delete cascade,organisation_id uuid not null references public.lb_organisations(id) on delete cascade,
 provider text not null check(provider in ('google_places','hunter')),priority_score numeric,status text not null default 'queued' check(status in ('queued','processing','completed','failed','blocked','no_contact')),
 attempts integer not null default 0,next_attempt_at timestamptz not null default now(),locked_at timestamptz,completed_at timestamptz,last_error text,last_result jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(opportunity_id,provider)
);
create index if not exists lb_contact_gap_jobs_status_idx on public.lb_contact_gap_jobs(provider,status,next_attempt_at,priority_score desc);
revoke all on public.lb_contact_gap_jobs from anon,authenticated;

create or replace function public.lb_refresh_web_crawl_targets_from_domains(p_limit integer default 1000) returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
 with targets as (select o.organisation_id,o.id opportunity_id,o.site_id,coalesce(org.website,'https://'||org.domain) url,o.enrichment_priority_score,row_number() over(order by o.enrichment_priority_score desc nulls last,o.id) rn from public.lb_opportunities o join public.lb_organisations org on org.id=o.organisation_id where (org.website is not null or org.domain is not null) and o.stage in ('identified','researching','contact_ready') and not exists(select 1 from public.lb_web_crawl_jobs w where w.organisation_id=o.organisation_id)),ins as (insert into public.lb_web_crawl_jobs(organisation_id,opportunity_id,site_id,url,priority_score,status,attempts,created_at,updated_at) select organisation_id,opportunity_id,site_id,url,enrichment_priority_score,'queued',0,now(),now() from targets where rn<=greatest(1,least(2000,p_limit)) on conflict(organisation_id) do nothing returning id)
 select count(*) into v_count from ins;return v_count;end;$$;
revoke all on function public.lb_refresh_web_crawl_targets_from_domains(integer) from public,anon,authenticated;grant execute on function public.lb_refresh_web_crawl_targets_from_domains(integer) to service_role;

create or replace function public.lb_refresh_paid_gap_targets(p_limit integer default 1000) returns jsonb language plpgsql security definer set search_path=public as $$
declare vg integer:=0;vh integer:=0;begin
 perform public.lb_refresh_web_crawl_targets_from_domains(p_limit);
 with base as (select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and cp.type in ('phone','mobile') and not coalesce(cp.do_not_contact,false) and cp.verification_status in ('probable','verified') and coalesce(cp.confidence,0)>=80) good_phone,exists(select 1 from public.lb_osm_contact_jobs j where j.opportunity_id=e.opportunity_id and j.status in ('completed','no_match','failed')) osm_done,not exists(select 1 from public.lb_web_crawl_jobs w where w.organisation_id=o.organisation_id and w.status in ('queued','processing')) web_done from public.lb_enrichment_queue e join public.lb_opportunities o on o.id=e.opportunity_id),g as (insert into public.lb_contact_gap_jobs(opportunity_id,site_id,organisation_id,provider,priority_score,status,next_attempt_at,updated_at) select opportunity_id,site_id,organisation_id,'google_places',enrichment_priority_score,'queued',now(),now() from base where not good_phone and osm_done and web_done order by enrichment_priority_score desc nulls last limit greatest(1,least(2000,p_limit)) on conflict(opportunity_id,provider) do nothing returning id) select count(*) into vg from g;
 with base as (select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,org.domain,org.website,org.domain_confidence,org.domain_source,exists(select 1 from public.lb_contact_points cp where cp.organisation_id=o.organisation_id and cp.type='email' and not coalesce(cp.do_not_contact,false) and cp.verification_status in ('probable','verified','catch_all') and coalesce(cp.confidence,0)>=80) good_email,not exists(select 1 from public.lb_web_crawl_jobs w where w.organisation_id=o.organisation_id and w.status in ('queued','processing')) web_done from public.lb_enrichment_queue e join public.lb_opportunities o on o.id=e.opportunity_id join public.lb_organisations org on org.id=o.organisation_id),h as (insert into public.lb_contact_gap_jobs(opportunity_id,site_id,organisation_id,provider,priority_score,status,next_attempt_at,updated_at) select opportunity_id,site_id,organisation_id,'hunter',enrichment_priority_score,'queued',now(),now() from base where not good_email and web_done and domain is not null and (coalesce(domain_confidence,0)>=80 or domain_source in ('website_crawl','openstreetmap','google_places','manual','trusted_import') or website is not null) order by enrichment_priority_score desc nulls last limit greatest(1,least(2000,p_limit)) on conflict(opportunity_id,provider) do nothing returning id) select count(*) into vh from h;
 return jsonb_build_object('google_places_added',vg,'hunter_added',vh);end;$$;
revoke all on function public.lb_refresh_paid_gap_targets(integer) from public,anon,authenticated;grant execute on function public.lb_refresh_paid_gap_targets(integer) to service_role;
create or replace view public.lb_contact_gap_progress with (security_invoker=true) as select provider,count(*) total,count(*) filter(where status='queued') queued,count(*) filter(where status='processing') processing,count(*) filter(where status='completed') completed,count(*) filter(where status='no_contact') no_contact,count(*) filter(where status='failed') failed,count(*) filter(where status='blocked') blocked from public.lb_contact_gap_jobs group by provider;
grant select on public.lb_contact_gap_progress to anon,authenticated;

create or replace function public.lb_kick_contact_gap_batch(p_provider text default null,p_batch integer default 2) returns bigint language plpgsql security definer set search_path=public,net as $$
declare v_request_id bigint;v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhkb3FjbHJ3ZGR1bmNqYXh0aXhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwMjkyNjMsImV4cCI6MjA5NjYwNTI2M30.vLCzN7-eNJh32tvy0zySDGX5bp6X1v9WlST59BSmIkk';begin
 if p_provider is not null and p_provider not in ('google_places','hunter') then raise exception 'invalid provider';end if;
 select net.http_post(url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/process-contact-gap-batch',body:=jsonb_strip_nulls(jsonb_build_object('batch_size',greatest(1,least(3,p_batch)),'provider',p_provider)),params:='{}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer '||v_anon),timeout_milliseconds:=120000) into v_request_id;return v_request_id;end;$$;
revoke all on function public.lb_kick_contact_gap_batch(text,integer) from public,anon,authenticated;grant execute on function public.lb_kick_contact_gap_batch(text,integer) to service_role;

select public.lb_refresh_contact_review_queue();
select public.lb_refresh_web_crawl_targets_from_domains(1000);
