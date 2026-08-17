do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname='landbank-planning-bulk-import' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid);end if;
  perform cron.schedule(
    'landbank-planning-bulk-import',
    '*/3 * * * *',
    'select public.lb_kick_planning_import(null);'
  );
end $$;
