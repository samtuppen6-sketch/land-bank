create or replace function public.lb_apply_agricultural_classification()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  if not exists(select 1 from public.lb_constraint_imports where dataset='agricultural-land-classification' and status='completed') then raise exception 'Agricultural Land Classification import is not complete';end if;
  with matches as (
    select s.id site_id,
      case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end grade_label,
      case
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 1%' then 10
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 2%' then 20
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 3a%' then 35
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 3b%' then 75
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 4%' then 90
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 5%' then 100
        else 60 end::numeric score,
      row_number() over(partition by s.id order by case
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 1%' then 10
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 2%' then 20
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 3a%' then 35
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 3b%' then 75
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 4%' then 90
        when lower(case when position('/' in f.reference)>0 then split_part(f.reference,'/',2) else f.reference end) like '%grade 5%' then 100
        else 60 end asc) rn
    from public.lb_sites s join public.lb_constraint_features f on f.dataset='agricultural-land-classification'
    where s.lat is not null and s.lng is not null and st_intersects(f.geometry,st_setsrid(st_makepoint(s.lng,s.lat),4326))
  ), upd as (
    update public.lb_sites s set agricultural_grade=m.grade_label,agricultural_score=m.score,updated_at=now() from matches m where m.rn=1 and s.id=m.site_id returning s.id
  ) select count(*) into v_count from upd;
  return v_count;
end;$$;
select public.lb_apply_agricultural_classification();
select public.lb_refresh_origination_scores();