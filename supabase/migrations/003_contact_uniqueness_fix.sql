-- LandBank V2: a phone/email can legitimately be shared by related farm companies.
-- Scope uniqueness to the owning organisation/person instead of globally.

alter table public.lb_contact_points
  drop constraint if exists lb_contact_points_type_value_key;

create unique index if not exists lb_contact_points_org_type_value_uq
  on public.lb_contact_points(organisation_id, type, value)
  where organisation_id is not null;

create unique index if not exists lb_contact_points_person_type_value_uq
  on public.lb_contact_points(person_id, type, value)
  where person_id is not null;

create index if not exists lb_contact_points_type_value_idx
  on public.lb_contact_points(type, value);
