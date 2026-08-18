-- After clean batch testing, increase the targeted HMLR INSPIRE screen from 5 to 10 sites/minute.

do $$
declare j record;
begin
  for j in select jobid from cron.job where jobname='landbank-inspire-spatial-screen' loop
    perform cron.unschedule(j.jobid);
  end loop;
end$$;

select cron.schedule(
  'landbank-inspire-spatial-screen',
  '* * * * *',
  'select public.lb_run_inspire_spatial_batch(10);'
);
