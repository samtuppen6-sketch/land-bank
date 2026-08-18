update public.lb_grid_source_imports set page_size=50,updated_at=now() where source_name='npg_generation_headroom_2026';
update public.lb_grid_area_imports set page_size=20,updated_at=now() where source_name='ssen_sepd_primary_areas_2025';

do $$ declare v_jobid bigint; begin
  select jobid into v_jobid from cron.job where jobname='landbank-solar-screen' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid);end if;
  perform cron.schedule('landbank-solar-screen','* * * * *','select public.lb_kick_solar_batch(15);');
  select jobid into v_jobid from cron.job where jobname='landbank-flood-screen' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid);end if;
  perform cron.schedule('landbank-flood-screen','* * * * *','select public.lb_run_flood_batch(10);');
end $$;
