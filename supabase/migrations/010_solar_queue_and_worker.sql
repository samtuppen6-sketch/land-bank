-- Step 2: keep national technical evidence layers explicit.
-- The initial generic queue becomes the PVGIS solar-yield queue.

update public.lb_assessment_queue
set job_type='solar_screen', updated_at=now()
where job_type='technical_screen';

drop view if exists public.lb_assessment_progress;
create view public.lb_assessment_progress as
select
  job_type,
  count(*) as total,
  count(*) filter (where status='queued') as queued,
  count(*) filter (where status='processing') as processing,
  count(*) filter (where status='completed') as completed,
  count(*) filter (where status='failed') as failed,
  round(100.0 * count(*) filter (where status='completed') / nullif(count(*),0), 1) as completion_pct
from public.lb_assessment_queue
group by job_type;

grant select on public.lb_assessment_progress to anon, authenticated;

update public.lb_assessment_queue q
set status='completed', completed_at=coalesce(q.completed_at,now()), locked_at=null,
    last_error=null, updated_at=now()
from public.lb_sites s
where q.site_id=s.id and q.job_type='solar_screen' and s.solar_score is not null;

-- A direct Postgres/PVGIS worker was deliberately retired after live testing
-- showed a TLS incompatibility in the PostgreSQL http extension. The production
-- portfolio worker therefore runs in Supabase Edge Runtime, which successfully
-- reaches PVGIS, and is kicked asynchronously through pg_net.
