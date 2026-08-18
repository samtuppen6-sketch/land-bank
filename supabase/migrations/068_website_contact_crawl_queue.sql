-- LandBank V2: free published-contact enrichment from known/trusted business websites.
create table if not exists public.lb_web_crawl_jobs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.lb_organisations(id) on delete cascade,
  opportunity_id uuid references public.lb_opportunities(id) on delete cascade,
  site_id uuid references public.lb_sites(id) on delete cascade,
  url text not null,
  priority_score numeric,
  status text not null default 'queued' check (status in ('queued','processing','completed','failed','skipped')),
  attempts integer not null default 0,
  locked_at timestamptz,
  completed_at timestamptz,
  last_error text,
  last_result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id)
);
create index if not exists lb_web_crawl_jobs_queue_idx on public.lb_web_crawl_jobs(status,priority_score desc,created_at);
revoke all on public.lb_web_crawl_jobs from anon,authenticated;

insert into public.lb_web_crawl_jobs(organisation_id,opportunity_id,site_id,url,priority_score)
select o.organisation_id,o.id,o.site_id,coalesce(org.website,cp.value),coalesce(o.call_priority_score,o.enrichment_priority_score,0)
from public.lb_opportunities o
join public.lb_organisations org on org.id=o.organisation_id
left join lateral (
  select value from public.lb_contact_points c
  where c.organisation_id=o.organisation_id and c.type='website' and not coalesce(c.do_not_contact,false)
  order by c.is_primary desc nulls last,c.confidence desc nulls last
  limit 1
) cp on true
where coalesce(org.website,cp.value) is not null
on conflict (organisation_id) do update set
  url=excluded.url,
  opportunity_id=excluded.opportunity_id,
  site_id=excluded.site_id,
  priority_score=excluded.priority_score,
  updated_at=now();