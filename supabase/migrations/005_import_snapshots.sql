-- LandBank V2 legacy-import provenance.
-- The http extension lets Supabase fetch the fixed public source JSON directly.

create extension if not exists http with schema extensions;

create table if not exists public.lb_import_snapshots (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  source_url text not null,
  source_sha text,
  payload jsonb not null,
  record_count integer,
  fetched_at timestamptz default now()
);

create index if not exists lb_import_snapshots_source_idx
  on public.lb_import_snapshots(source, fetched_at desc);
