create table if not exists public.lb_assessment_queue (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  job_type text not null default 'technical_screen',
  status text not null default 'queued' check (status in ('queued','processing','completed','failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  completed_at timestamptz,
  last_error text,
  last_result jsonb default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(site_id, job_type)
);

create index if not exists lb_assessment_queue_work_idx
  on public.lb_assessment_queue(status, next_attempt_at, attempts)
  where status in ('queued','failed');

insert into public.lb_assessment_queue(site_id, job_type, status)
select id, 'technical_screen', 'queued'
from public.lb_sites
on conflict (site_id, job_type) do nothing;

create or replace view public.lb_assessment_progress as
select
  count(*) as total,
  count(*) filter (where status='queued') as queued,
  count(*) filter (where status='processing') as processing,
  count(*) filter (where status='completed') as completed,
  count(*) filter (where status='failed') as failed,
  round(100.0 * count(*) filter (where status='completed') / nullif(count(*),0), 1) as completion_pct
from public.lb_assessment_queue
where job_type='technical_screen';

revoke all on public.lb_assessment_queue from anon, authenticated;
grant select on public.lb_assessment_progress to anon, authenticated;
