-- Final launch hygiene discovered by the Top-100 duplicate/contact audit.
-- Keep suspect evidence for audit, but prevent it being used for calling.
update public.lb_contact_points
set verification_status='invalid',confidence=0,do_not_contact=true,is_primary=false,
    label=coalesce(label,'')||' [quarantined domain mismatch]'
where organisation_id in (
  '7b94d5d7-3698-4e6a-b563-e781d98d49ed'::uuid,
  '3a4408c5-8fdc-41c2-92f0-85d9397de1e6'::uuid,
  'a55ff811-cdf9-4e20-9df2-3f1d84a6c387'::uuid
)
and source_url ilike '%orchards.demat.org.uk%';

update public.lb_organisations
set website=null,domain=null,domain_source=null,domain_confidence=null,domain_checked_at=now(),updated_at=now()
where id in (
  '7b94d5d7-3698-4e6a-b563-e781d98d49ed'::uuid,
  '3a4408c5-8fdc-41c2-92f0-85d9397de1e6'::uuid,
  'a55ff811-cdf9-4e20-9df2-3f1d84a6c387'::uuid
)
and domain='orchards.demat.org.uk';

update public.lb_contact_review_queue q
set status='rejected',reviewed_at=now(),
    reviewer_notes='Rejected automatically: unrelated school-domain attribution detected during final call-readiness audit',updated_at=now()
where contact_point_id in (
  select id from public.lb_contact_points
  where organisation_id in (
    '7b94d5d7-3698-4e6a-b563-e781d98d49ed'::uuid,
    '3a4408c5-8fdc-41c2-92f0-85d9397de1e6'::uuid,
    'a55ff811-cdf9-4e20-9df2-3f1d84a6c387'::uuid
  ) and source_url ilike '%orchards.demat.org.uk%'
);

with allnorm as (
 select id,organisation_id,type,value,
        btrim(regexp_replace(regexp_replace(replace(replace(value,'%20',' '),'%2B','+'),'^https?://','','i'),'^//','')) new_value,
        row_number() over(
          partition by organisation_id,type,btrim(regexp_replace(regexp_replace(replace(replace(value,'%20',' '),'%2B','+'),'^https?://','','i'),'^//',''))
          order by case when value like '%\%%' escape '\' then 1 else 0 end,id
        ) rn
 from public.lb_contact_points where type in ('phone','mobile')
), doomed as (
 select id from allnorm where rn>1 and value like '%\%%' escape '\'
)
delete from public.lb_contact_points c using doomed d where c.id=d.id;

with malformed as (
  select id,btrim(regexp_replace(regexp_replace(replace(replace(value,'%20',' '),'%2B','+'),'^https?://','','i'),'^//','')) new_value
  from public.lb_contact_points
  where type in ('phone','mobile') and value like '%\%%' escape '\'
)
update public.lb_contact_points c set value=m.new_value from malformed m where c.id=m.id;

select public.lb_refresh_origination_scores();