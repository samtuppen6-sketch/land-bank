alter table public.lb_sites
  add column if not exists site_potential_score numeric,
  add column if not exists site_potential_completeness numeric,
  add column if not exists site_potential_confidence numeric,
  add column if not exists site_potential_reasons jsonb not null default '[]'::jsonb;

alter table public.lb_opportunities
  add column if not exists contactability_score numeric,
  add column if not exists call_priority_score numeric,
  add column if not exists enrichment_priority_score numeric,
  add column if not exists call_rank integer,
  add column if not exists why_calling jsonb not null default '[]'::jsonb;