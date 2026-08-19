alter table public.lb_qualifications
  add column if not exists preferred_contact_name text,
  add column if not exists preferred_contact_mobile text;

comment on column public.lb_qualifications.preferred_contact_name is 'Best person to call for this qualified opportunity / handover. Optional; does not gate handover readiness.';
comment on column public.lb_qualifications.preferred_contact_mobile is 'Preferred direct or mobile contact number for the handover contact. Optional; does not gate handover readiness.';
