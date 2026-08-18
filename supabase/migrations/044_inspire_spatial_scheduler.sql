-- Run a conservative targeted HMLR INSPIRE screen over the strong CCOD ownership cohort.
-- Five sites per minute avoids hammering the public WMS and keeps runs short/non-overlapping.

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
  'select public.lb_run_inspire_spatial_batch(5);'
);
