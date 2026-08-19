-- Keep the production scheduler from bunching heavyweight LandBank jobs together.
-- Completed one-shot assessment queues no longer need minute-by-minute kickers.

create index if not exists lb_assessment_queue_processing_lock_idx
  on public.lb_assessment_queue (job_type, locked_at)
  where status = 'processing';

do $$
declare
  j record;
begin
  for j in
    select jobid, jobname
    from cron.job
    where jobname in (
      'landbank-solar-screen',
      'landbank-flood-screen',
      'landbank-planning-point-screen',
      'landbank-wales-point-screen'
    )
  loop
    perform cron.unschedule(j.jobid);
  end loop;

  select jobid into j from cron.job where jobname='landbank-ssen-grid-match' limit 1;
  if found then perform cron.alter_job(j.jobid, schedule => '1-59/5 * * * *'); end if;

  select jobid into j from cron.job where jobname='landbank-spen-grid-match' limit 1;
  if found then perform cron.alter_job(j.jobid, schedule => '2-59/5 * * * *'); end if;

  select jobid into j from cron.job where jobname='landbank-origination-score-refresh' limit 1;
  if found then perform cron.alter_job(j.jobid, schedule => '3-59/5 * * * *'); end if;

  select jobid into j from cron.job where jobname='landbank-handover-readiness' limit 1;
  if found then perform cron.alter_job(j.jobid, schedule => '4-59/5 * * * *'); end if;

  select jobid into j from cron.job where jobname='landbank-export-value-refresh' limit 1;
  if found then perform cron.alter_job(j.jobid, schedule => '0-59/5 * * * *'); end if;
end $$;