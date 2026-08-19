create schema if not exists private;
revoke all on schema private from public;

create materialized view private.lb_best_contact_points_cache as
select contact_point_id,
       organisation_id,
       person_id,
       type,
       value,
       label,
       is_primary,
       verification_status,
       discovery_method,
       provider,
       source_url,
       confidence,
       found_at,
       verified_at,
       do_not_contact,
       review_status,
       review_risk,
       provider_count,
       trusted_provider_count,
       quality_score,
       trust_label,
       trust_reason,
       quality_rank
from (
  select q.*,
         row_number() over (
           partition by q.organisation_id, q.type
           order by case q.trust_label
                      when 'confirmed' then 5
                      when 'trusted' then 4
                      when 'probable' then 3
                      when 'review' then 2
                      else 0
                    end desc,
                    q.quality_score desc,
                    q.verified_at desc nulls last,
                    q.found_at desc nulls last,
                    q.contact_point_id
         ) as quality_rank
  from public.lb_contact_quality q
  where not coalesce(q.do_not_contact,false)
    and q.trust_label <> 'rejected'
) x
where quality_rank=1
with data;

create unique index lb_best_contact_points_cache_contact_uq
  on private.lb_best_contact_points_cache(contact_point_id);
create index lb_best_contact_points_cache_org_type_idx
  on private.lb_best_contact_points_cache(organisation_id,type,quality_score desc);

create or replace view public.lb_best_contact_points as
select contact_point_id,
       organisation_id,
       person_id,
       type,
       value,
       label,
       is_primary,
       verification_status,
       discovery_method,
       provider,
       source_url,
       confidence,
       found_at,
       verified_at,
       do_not_contact,
       review_status,
       review_risk,
       provider_count,
       trusted_provider_count,
       quality_score,
       trust_label,
       trust_reason,
       quality_rank
from private.lb_best_contact_points_cache;

do $$
begin
  perform cron.unschedule('landbank-sales-contact-cache-refresh');
exception when others then null;
end $$;

select cron.schedule(
  'landbank-sales-contact-cache-refresh',
  '*/5 * * * *',
  $$refresh materialized view concurrently private.lb_best_contact_points_cache;$$
);