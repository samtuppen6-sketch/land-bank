-- Northern Powergrid import is finite and complete; retire its no-op recurring job.
do $$ declare v_jobid bigint; begin
  select jobid into v_jobid from cron.job where jobname='landbank-npg-grid-import' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid);end if;
end $$;

-- Proven-stable polygon importers can use larger pages.
update public.lb_grid_source_imports set page_size=50,updated_at=now() where source_name='npg_generation_headroom_2026';
update public.lb_grid_area_imports set page_size=20,updated_at=now() where source_name='ssen_sepd_primary_areas_2025';
update public.lb_grid_area_imports set page_size=25,updated_at=now() where source_name='spen_spm_primary_areas_2026';
