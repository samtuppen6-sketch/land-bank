create or replace view public.lb_contact_quality with (security_invoker=false) as
with base as (
  select c.*,
    case
      when c.type in ('phone','mobile') then regexp_replace(c.value,'[^0-9]','','g')
      when c.type='email' then lower(btrim(c.value))
      when c.type='website' then regexp_replace(regexp_replace(lower(btrim(c.value)),'^https?://',''),'[/].*$','')
      else lower(btrim(c.value))
    end as normalized_value,
    (c.provider in ('website_crawl','hunter','foursquare_os','openstreetmap','google_places')
      or c.discovery_method in ('published_website','hunter_domain_search','foursquare_os_iceberg_match','osm_public_contact','google_places_text_search')) as trusted_source
  from public.lb_contact_points c
), corroboration as (
  select organisation_id,type,normalized_value,
    count(distinct coalesce(provider,discovery_method,'unknown')) as provider_count,
    count(distinct case when trusted_source then coalesce(provider,discovery_method,'trusted') end) as trusted_provider_count
  from base
  where normalized_value is not null and normalized_value<>''
  group by organisation_id,type,normalized_value
)
select b.id as contact_point_id,b.organisation_id,b.person_id,b.type,b.value,b.label,b.is_primary,
       b.verification_status,b.discovery_method,b.provider,b.source_url,b.confidence,b.found_at,b.verified_at,b.do_not_contact,
       rq.status as review_status,rq.risk_score as review_risk,
       coalesce(c.provider_count,1) as provider_count,coalesce(c.trusted_provider_count,0) as trusted_provider_count,
       greatest(0,least(100,
         coalesce(b.confidence,50)
         + case b.verification_status when 'verified' then 15 when 'probable' then 10 when 'catch_all' then 3 when 'invalid' then -100 else 0 end
         + case when b.trusted_source then 10 else 0 end
         + case when coalesce(c.trusted_provider_count,0)>=2 then 15 else 0 end
         + case when rq.status='approved' then 8 when rq.status='rejected' then -100 when rq.status='pending' then -15 else 0 end
         + case when b.discovery_method in ('legacy_contact_dataset','inferred_legacy_email') then -8 else 0 end
       ))::numeric as quality_score,
       case
         when b.verification_status='invalid' or rq.status='rejected' then 'rejected'
         when coalesce(c.trusted_provider_count,0)>=2 and coalesce(b.confidence,0)>=75 then 'confirmed'
         when rq.status='pending' and not b.trusted_source then 'review'
         when b.trusted_source and b.verification_status in ('verified','probable') and coalesce(b.confidence,0)>=80 then 'trusted'
         when (b.verification_status='probable' and coalesce(b.confidence,0)>=75) or (b.trusted_source and coalesce(b.confidence,0)>=75) then 'probable'
         else 'review'
       end as trust_label,
       case
         when b.verification_status='invalid' or rq.status='rejected' then 'Rejected or invalid contact'
         when coalesce(c.trusted_provider_count,0)>=2 and coalesce(b.confidence,0)>=75 then 'Independently corroborated by multiple trusted sources'
         when rq.status='pending' and not b.trusted_source then 'Legacy or weak-provenance contact awaiting independent confirmation'
         when b.provider='website_crawl' then 'Published on the organisation website'
         when b.provider='hunter' and b.verification_status='verified' then 'Verified email from Hunter against a trusted domain'
         when b.provider='foursquare_os' then 'Strong Foursquare OS place match using name, postcode and coordinates'
         when b.provider='openstreetmap' then 'Public OpenStreetMap business contact with strict identity match'
         when b.provider='google_places' then 'Strict Google Places business match'
         when b.discovery_method='legacy_contact_dataset' then 'Legacy contact retained; provenance needs caution unless corroborated'
         else 'Best available contact; provenance should be treated with caution'
       end as trust_reason
from base b
left join corroboration c on c.organisation_id=b.organisation_id and c.type=b.type and c.normalized_value=b.normalized_value
left join public.lb_contact_review_queue rq on rq.contact_point_id=b.id;

grant select on public.lb_contact_quality to anon,authenticated;

create or replace view public.lb_best_contact_points with (security_invoker=false) as
select * from (
  select q.*, row_number() over(
    partition by q.organisation_id,q.type
    order by
      case q.trust_label when 'confirmed' then 5 when 'trusted' then 4 when 'probable' then 3 when 'review' then 2 else 0 end desc,
      q.quality_score desc,
      q.verified_at desc nulls last,
      q.found_at desc nulls last,
      q.contact_point_id
  ) as quality_rank
  from public.lb_contact_quality q
  where not coalesce(q.do_not_contact,false)
    and q.trust_label<>'rejected'
) x where quality_rank=1;

grant select on public.lb_best_contact_points to anon,authenticated;