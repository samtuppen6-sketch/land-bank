create table if not exists public.lb_contact_validations (
  id uuid primary key default gen_random_uuid(),
  contact_point_id uuid not null references public.lb_contact_points(id) on delete cascade,
  organisation_id uuid not null references public.lb_organisations(id) on delete cascade,
  provider text not null,
  validation_status text not null check (validation_status in ('confirmed','different_number','no_phone','ambiguous','no_match','error')),
  candidate_value text,
  matched_value text,
  match_score numeric,
  identity_score numeric,
  source_ref text,
  source_url text,
  details jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(contact_point_id,provider)
);

create index if not exists lb_contact_validations_org_idx on public.lb_contact_validations(organisation_id,validation_status);
create index if not exists lb_contact_validations_contact_idx on public.lb_contact_validations(contact_point_id,validation_status);
alter table public.lb_contact_validations enable row level security;
revoke all on public.lb_contact_validations from anon,authenticated;

drop view if exists public.lb_phone_revalidation_queue;
create view public.lb_phone_revalidation_queue with (security_invoker=false) as
select distinct on (sw.organisation_id)
  sw.opportunity_id,sw.site_id,sw.organisation_id,sw.site_name,sw.organisation_name,
  sw.address_line,sw.town,sw.county,sw.postcode,sw.lat,sw.lng,sw.call_priority_score,
  sw.company_number,sw.domain,sw.website,sw.decision_makers,
  b.contact_point_id,b.type as contact_type,b.value as candidate_phone,
  b.provider as original_provider,b.discovery_method as original_discovery_method,
  b.confidence as original_confidence,b.review_status,b.quality_score,b.trust_label
from public.lb_sales_workspace sw
join public.lb_best_contact_points b
  on b.organisation_id=sw.organisation_id and b.type in ('phone','mobile')
where b.trust_label='review'
  and sw.call_priority_score>=70
  and not exists (
    select 1 from public.lb_contact_validations v
    where v.contact_point_id=b.contact_point_id and v.provider='google_places_revalidation'
  )
order by sw.organisation_id,b.quality_score desc,sw.call_priority_score desc;
revoke all on public.lb_phone_revalidation_queue from anon,authenticated;

create or replace view public.lb_contact_quality as
with base as (
  select c.id,c.organisation_id,c.person_id,c.type,c.value,c.label,c.is_primary,
    c.verification_status,c.discovery_method,c.provider,c.source_url,c.confidence,
    c.found_at,c.verified_at,c.do_not_contact,
    case
      when c.type in ('phone','mobile') then regexp_replace(c.value,'[^0-9]','','g')
      when c.type='email' then lower(btrim(c.value))
      when c.type='website' then regexp_replace(regexp_replace(lower(btrim(c.value)),'^https?://',''),'[/].*$','')
      else lower(btrim(c.value))
    end normalized_value,
    (c.provider in ('website_crawl','hunter','foursquare_os','openstreetmap','google_places')
      or c.discovery_method in ('published_website','hunter_domain_search','foursquare_os_iceberg_match','osm_public_contact','google_places_text_search')) trusted_source
  from public.lb_contact_points c
), corroboration as (
  select organisation_id,type,normalized_value,
    count(distinct coalesce(provider,discovery_method,'unknown')) provider_count,
    count(distinct case when trusted_source then coalesce(provider,discovery_method,'trusted') end) trusted_provider_count
  from base
  where normalized_value is not null and normalized_value<>''
  group by organisation_id,type,normalized_value
), validations as (
  select contact_point_id,
    count(*) filter(where validation_status='confirmed') confirmed_validation_count,
    string_agg(distinct provider,', ' order by provider) filter(where validation_status='confirmed') confirmed_validation_sources,
    max(checked_at) last_validation_at
  from public.lb_contact_validations
  group by contact_point_id
)
select b.id contact_point_id,b.organisation_id,b.person_id,b.type,b.value,b.label,b.is_primary,
  b.verification_status,b.discovery_method,b.provider,b.source_url,b.confidence,b.found_at,
  b.verified_at,b.do_not_contact,rq.status review_status,rq.risk_score review_risk,
  coalesce(c.provider_count,1)+coalesce(v.confirmed_validation_count,0) provider_count,
  coalesce(c.trusted_provider_count,0)+coalesce(v.confirmed_validation_count,0) trusted_provider_count,
  greatest(0,least(100,
    coalesce(b.confidence,50)
    + case b.verification_status when 'verified' then 15 when 'probable' then 10 when 'catch_all' then 3 when 'invalid' then -100 else 0 end
    + case when b.trusted_source then 10 else 0 end
    + case when coalesce(c.trusted_provider_count,0)>=2 then 15 else 0 end
    + case when coalesce(v.confirmed_validation_count,0)>=1 then 25 else 0 end
    + case when rq.status='approved' then 8 when rq.status='rejected' then -100 when rq.status='pending' and coalesce(v.confirmed_validation_count,0)=0 then -15 else 0 end
    + case when b.discovery_method in ('legacy_contact_dataset','inferred_legacy_email') then -8 else 0 end
  )) quality_score,
  case
    when b.verification_status='invalid' or rq.status='rejected' then 'rejected'
    when coalesce(v.confirmed_validation_count,0)>=1 and coalesce(b.confidence,0)>=55 then 'confirmed'
    when coalesce(c.trusted_provider_count,0)>=2 and coalesce(b.confidence,0)>=75 then 'confirmed'
    when rq.status='pending' and not b.trusted_source then 'review'
    when b.trusted_source and b.verification_status in ('verified','probable') and coalesce(b.confidence,0)>=80 then 'trusted'
    when (b.verification_status='probable' and coalesce(b.confidence,0)>=75) or (b.trusted_source and coalesce(b.confidence,0)>=75) then 'probable'
    else 'review'
  end trust_label,
  case
    when b.verification_status='invalid' or rq.status='rejected' then 'Rejected or invalid contact'
    when coalesce(v.confirmed_validation_count,0)>=1 then 'Existing contact independently revalidated by '||coalesce(v.confirmed_validation_sources,'trusted source')
    when coalesce(c.trusted_provider_count,0)>=2 then 'Independently corroborated by multiple trusted sources'
    when rq.status='pending' and not b.trusted_source then 'Legacy or weak-provenance contact awaiting independent confirmation'
    when b.provider='website_crawl' then 'Published on the organisation website'
    when b.provider='hunter' and b.verification_status='verified' then 'Verified email from Hunter against a trusted domain'
    when b.provider='foursquare_os' then 'Strong Foursquare OS place match using name, postcode and coordinates'
    when b.provider='openstreetmap' then 'Public OpenStreetMap business contact with strict identity match'
    when b.provider='google_places' then 'Strict Google Places business match'
    when b.discovery_method='legacy_contact_dataset' then 'Legacy contact retained; provenance needs caution unless corroborated'
    else 'Best available contact; provenance should be treated with caution'
  end trust_reason
from base b
left join corroboration c on c.organisation_id=b.organisation_id and c.type=b.type and c.normalized_value=b.normalized_value
left join public.lb_contact_review_queue rq on rq.contact_point_id=b.id
left join validations v on v.contact_point_id=b.id;

create or replace function public.lb_refresh_contact_review_queue()
returns integer language plpgsql security definer set search_path='public' as $$
declare v_count integer;
begin
  update public.lb_contact_review_queue q
     set status='approved',reviewer_notes='Auto-approved: independently revalidated by trusted source',reviewed_at=now(),updated_at=now()
   where q.status='pending'
     and exists(select 1 from public.lb_contact_validations v where v.contact_point_id=q.contact_point_id and v.validation_status='confirmed');

  update public.lb_contact_review_queue q
     set status='approved',reviewer_notes='Auto-approved: independently cross-confirmed by trusted source',reviewed_at=now(),updated_at=now()
   where q.status='pending'
     and exists(
       select 1 from public.lb_contact_points cp
       join public.lb_contact_points x on x.organisation_id=cp.organisation_id and x.type=cp.type and x.id<>cp.id
       where cp.id=q.contact_point_id
         and lower(regexp_replace(x.value,'[^a-zA-Z0-9@.+]','','g'))=lower(regexp_replace(cp.value,'[^a-zA-Z0-9@.+]','','g'))
         and x.provider in ('website_crawl','hunter','openstreetmap','google_places','foursquare_os')
         and coalesce(x.confidence,0)>=80
         and x.verification_status in ('probable','verified','catch_all')
     );

  with candidates as (
    select cp.id contact_point_id,cp.organisation_id,
      case when cp.provider ilike 'Google Places —%' then 'Legacy Google Places contact is not independently cross-checked'
           when coalesce(cp.confidence,0)<70 then 'Low-confidence contact'
           when coalesce(cp.verification_status,'unknown')='unknown' then 'Unverified contact'
           when cp.source_url is null and cp.provider not in ('website_crawl','hunter','openstreetmap','google_places','foursquare_os') then 'Contact has weak source provenance'
           else 'Contact requires provenance review' end reason,
      case when cp.provider ilike 'Google Places —%' and cp.verification_status='unknown' then 85
           when cp.provider ilike 'Google Places —%' then 65
           when coalesce(cp.confidence,0)<50 then 90
           when coalesce(cp.confidence,0)<70 then 75
           when coalesce(cp.verification_status,'unknown')='unknown' then 70
           else 55 end::numeric risk_score
    from public.lb_contact_points cp
    where coalesce(cp.do_not_contact,false)=false
      and (cp.provider ilike 'Google Places —%' or coalesce(cp.confidence,0)<70 or coalesce(cp.verification_status,'unknown')='unknown'
           or (cp.source_url is null and cp.provider not in ('website_crawl','hunter','openstreetmap','google_places','foursquare_os')))
      and not exists(select 1 from public.lb_contact_validations v where v.contact_point_id=cp.id and v.validation_status='confirmed')
      and not exists (
        select 1 from public.lb_contact_points x
        where x.organisation_id=cp.organisation_id and x.type=cp.type and x.id<>cp.id
          and lower(regexp_replace(x.value,'[^a-zA-Z0-9@.+]','','g'))=lower(regexp_replace(cp.value,'[^a-zA-Z0-9@.+]','','g'))
          and x.provider in ('website_crawl','hunter','openstreetmap','google_places','foursquare_os')
          and coalesce(x.confidence,0)>=80 and x.verification_status in ('probable','verified','catch_all')
      )
  ), ins as (
    insert into public.lb_contact_review_queue(contact_point_id,organisation_id,reason,risk_score,updated_at)
    select contact_point_id,organisation_id,reason,risk_score,now() from candidates
    on conflict(contact_point_id) do update set reason=excluded.reason,risk_score=excluded.risk_score,updated_at=now()
    returning id
  ) select count(*) into v_count from ins;
  return v_count;
end;$$;
