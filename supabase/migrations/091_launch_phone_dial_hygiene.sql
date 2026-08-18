-- Repair trusted legacy website phone strings that pre-date the stricter crawler normaliser.
insert into public.lb_contact_points(organisation_id,type,value,label,is_primary,verification_status,discovery_method,provider,source_url,confidence,found_at,verified_at,do_not_contact)
select organisation_id,type,
       case id::text
         when '1a8dd33c-6796-4897-ad7e-f1a53bda768d' then '01245 475181'
         when '605b704d-e31c-4fa0-bbac-74f6b4092a3f' then '01621 892305'
         when '7066ad61-c15f-4510-a82a-955e0392e73c' then '01842 862068'
         when '719a61ce-0d88-4fa1-92bf-2f0bcd2eddae' then '01942 882667'
       end,
       coalesce(label,'Website phone')||' [normalised]',is_primary,'probable',discovery_method,provider,source_url,greatest(confidence,90),found_at,verified_at,false
from public.lb_contact_points
where id in (
 '1a8dd33c-6796-4897-ad7e-f1a53bda768d'::uuid,
 '605b704d-e31c-4fa0-bbac-74f6b4092a3f'::uuid,
 '7066ad61-c15f-4510-a82a-955e0392e73c'::uuid,
 '719a61ce-0d88-4fa1-92bf-2f0bcd2eddae'::uuid
)
on conflict(organisation_id,type,value) do nothing;

insert into public.lb_contact_points(organisation_id,type,value,label,is_primary,verification_status,discovery_method,provider,source_url,confidence,found_at,do_not_contact)
select organisation_id,type,'01795 423981',coalesce(label,'Website phone')||' [split 1]',true,'probable',discovery_method,provider,source_url,92,found_at,false
from public.lb_contact_points where id='ced299ac-9e0b-4a37-8abc-c635a25bf90b'::uuid
on conflict(organisation_id,type,value) do nothing;

insert into public.lb_contact_points(organisation_id,type,value,label,is_primary,verification_status,discovery_method,provider,source_url,confidence,found_at,do_not_contact)
select organisation_id,type,'01795 506388',coalesce(label,'Website phone')||' [split 2]',false,'probable',discovery_method,provider,source_url,90,found_at,false
from public.lb_contact_points where id='ced299ac-9e0b-4a37-8abc-c635a25bf90b'::uuid
on conflict(organisation_id,type,value) do nothing;

update public.lb_contact_points
set verification_status='invalid',confidence=0,do_not_contact=true,is_primary=false,
    label=coalesce(label,'')||' [superseded malformed phone]'
where id in (
 '1a8dd33c-6796-4897-ad7e-f1a53bda768d'::uuid,
 '605b704d-e31c-4fa0-bbac-74f6b4092a3f'::uuid,
 '7066ad61-c15f-4510-a82a-955e0392e73c'::uuid,
 '719a61ce-0d88-4fa1-92bf-2f0bcd2eddae'::uuid,
 'ced299ac-9e0b-4a37-8abc-c635a25bf90b'::uuid
);

select public.lb_refresh_origination_scores();