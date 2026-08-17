do $$ declare v_jobid bigint; begin
  select jobid into v_jobid from cron.job where jobname='landbank-ssen-grid-match' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid);end if;
  perform cron.schedule('landbank-ssen-grid-match','*/5 * * * *','select public.lb_refresh_ssen_area_grid_matches();');
end $$;
