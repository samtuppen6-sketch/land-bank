alter table public.lb_sites
  add column if not exists planning_screen_score numeric,
  add column if not exists planning_score_confidence numeric,
  add column if not exists planning_screened_at timestamptz,
  add column if not exists planning_evidence_class text,
  add column if not exists planning_constraint_count integer;
create index if not exists lb_sites_planning_screen_idx on public.lb_sites(planning_screen_score);

insert into public.lb_assessment_queue(site_id,job_type,status,attempts,next_attempt_at)
select id,'planning_point','queued',0,now() from public.lb_sites
on conflict(site_id,job_type) do nothing;

-- The original national bulk-polygon pipeline is intentionally retired for the lean
-- origination workflow. Parcel-level due diligence belongs downstream after interest.
select cron.unschedule(jobid) from cron.job where jobname in ('landbank-planning-bulk-import','landbank-planning-finalize');