create table if not exists public.lb_enrichment_queue_jobs (
 id uuid primary key default gen_random_uuid(),opportunity_id uuid not null references public.lb_opportunities(id) on delete cascade,site_id uuid not null references public.lb_sites(id) on delete cascade,organisation_id uuid references public.lb_organisations(id) on delete cascade,priority_score numeric,providers text[] not null default array['companies_house','google_places','hunter']::text[],status text not null default 'queued' check(status in ('queued','processing','completed','failed','blocked')),attempts integer not null default 0,next_attempt_at timestamptz not null default now(),locked_at timestamptz,completed_at timestamptz,last_error text,last_result jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(opportunity_id)
);
create index if not exists lb_enrichment_queue_jobs_status_idx on public.lb_enrichment_queue_jobs(status,next_attempt_at,priority_score desc);
revoke all on public.lb_enrichment_queue_jobs from anon,authenticated;

create or replace function public.lb_refresh_enrichment_targets(p_limit integer default 1000)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  with targets as (
    select e.opportunity_id,e.site_id,o.organisation_id,e.enrichment_priority_score,row_number() over(order by e.enrichment_priority_score desc nulls last,e.opportunity_id) rn
    from public.lb_enrichment_queue e join public.lb_opportunities o on o.id=e.opportunity_id
  ), ins as (
    insert into public.lb_enrichment_queue_jobs(opportunity_id,site_id,organisation_id,priority_score,status,next_attempt_at,updated_at)
    select opportunity_id,site_id,organisation_id,enrichment_priority_score,'queued',now(),now() from targets where rn<=greatest(1,least(2000,p_limit))
    on conflict(opportunity_id) do update set priority_score=excluded.priority_score,organisation_id=excluded.organisation_id,site_id=excluded.site_id,updated_at=now() returning id
  ) select count(*) into v_count from ins;
  return v_count;
end;$$;
revoke all on function public.lb_refresh_enrichment_targets(integer) from public,anon,authenticated;
grant execute on function public.lb_refresh_enrichment_targets(integer) to service_role;
select public.lb_refresh_enrichment_targets(1000);

create or replace view public.lb_enrichment_target_progress as
select count(*) total_targets,count(*) filter(where status='queued') queued,count(*) filter(where status='processing') processing,count(*) filter(where status='completed') completed,count(*) filter(where status='failed') failed,count(*) filter(where status='blocked') blocked,round(avg(priority_score),1) mean_priority from public.lb_enrichment_queue_jobs;
grant select on public.lb_enrichment_target_progress to anon,authenticated;