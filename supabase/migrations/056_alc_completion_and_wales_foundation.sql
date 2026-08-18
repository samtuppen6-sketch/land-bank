do $$
declare v_count integer;
begin
  select count(*) into v_count from public.lb_constraint_features where dataset='agricultural-land-classification';
  if v_count>=585 then
    update public.lb_constraint_imports
    set status='completed',next_offset=v_count,records_imported=v_count,last_error=null,completed_at=coalesce(completed_at,now()),updated_at=now()
    where dataset='agricultural-land-classification';
    perform public.lb_apply_agricultural_classification();
  end if;
end $$;

alter table public.lb_sites
  add column if not exists osgb_easting numeric,
  add column if not exists osgb_northing numeric;

update public.lb_sites
set osgb_easting=st_x(st_transform(location_geom,27700)),
    osgb_northing=st_y(st_transform(location_geom,27700))
where location_geom is not null and (osgb_easting is null or osgb_northing is null);

insert into public.lb_assessment_queue(site_id,job_type,status,attempts,next_attempt_at)
select id,'wales_point','queued',0,now()
from public.lb_sites
where agricultural_score is null and lat is not null and lng is not null
on conflict(site_id,job_type) do nothing;