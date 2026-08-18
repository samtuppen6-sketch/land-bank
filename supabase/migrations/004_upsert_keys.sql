-- LandBank V2: full unique keys so PostgREST upserts can infer conflicts reliably.

 drop index if exists public.lb_sites_legacy_company_uq;
 drop index if exists public.lb_opps_legacy_company_uq;
 drop index if exists public.lb_contact_points_org_type_value_uq;
 drop index if exists public.lb_contact_points_person_type_value_uq;

create unique index if not exists lb_sites_legacy_company_uq
  on public.lb_sites(legacy_company_number);
create unique index if not exists lb_opps_legacy_company_uq
  on public.lb_opportunities(legacy_company_number);
create unique index if not exists lb_contact_points_org_type_value_uq
  on public.lb_contact_points(organisation_id, type, value);
create unique index if not exists lb_contact_points_person_type_value_uq
  on public.lb_contact_points(person_id, type, value);
