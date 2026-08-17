-- Run ten PVGIS site assessments every two minutes.
-- The Edge Function handles per-site retries and the queue tracks completion.

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname='landbank-solar-screen' limit 1;
  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'landbank-solar-screen',
    '*/2 * * * *',
    'select public.lb_kick_solar_batch(10);'
  );
end $$;
