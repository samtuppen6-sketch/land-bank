create table if not exists public.lb_grid_nodes (
  id uuid primary key default gen_random_uuid(),
  dno text not null,
  source_id text not null,
  name text,
  node_type text,
  voltage_kv numeric,
  lat double precision,
  lng double precision,
  location geography(point,4326),
  generation_headroom_mw numeric,
  demand_headroom_mw numeric,
  firm_capacity_mva numeric,
  peak_demand_mw numeric,
  connected_generation_mw numeric,
  accepted_generation_mw numeric,
  data_date date,
  confidence numeric,
  source_url text,
  raw_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(dno,source_id)
);
create index if not exists lb_grid_nodes_location_gix on public.lb_grid_nodes using gist(location);
create index if not exists lb_grid_nodes_dno_idx on public.lb_grid_nodes(dno);

create table if not exists public.lb_site_grid_matches (
  site_id uuid primary key references public.lb_sites(id) on delete cascade,
  grid_node_id uuid not null references public.lb_grid_nodes(id) on delete cascade,
  distance_km numeric,
  proximity_score numeric,
  headroom_score numeric,
  grid_score numeric,
  score_confidence numeric,
  assumptions jsonb not null default '{}'::jsonb,
  matched_at timestamptz not null default now()
);

alter table public.lb_sites
  add column if not exists grid_dno text,
  add column if not exists nearest_grid_node_id uuid references public.lb_grid_nodes(id),
  add column if not exists grid_distance_km numeric,
  add column if not exists grid_proximity_score numeric,
  add column if not exists grid_score_confidence numeric;

create or replace function public.lb_refresh_grid_matches(p_max_km numeric default 40)
returns integer
language plpgsql security definer set search_path=public
as $$
declare v_count integer;
begin
  with nearest as (
    select s.id site_id,n.id node_id,n.dno,n.generation_headroom_mw,ST_Distance(s.location,n.location)/1000.0 distance_km
    from public.lb_sites s cross join lateral (
      select g.* from public.lb_grid_nodes g where g.location is not null and s.location is not null and ST_DWithin(s.location,g.location,p_max_km*1000)
      order by s.location <-> g.location limit 1
    ) n where s.location is not null
  ),scored as (
    select *,round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1) proximity_score,
      case when generation_headroom_mw is not null then round(greatest(0,least(100,(generation_headroom_mw/10.0)*100))::numeric,1) else null end headroom_score from nearest
  ),upserted as (
    insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
    select site_id,node_id,round(distance_km::numeric,2),proximity_score,headroom_score,case when headroom_score is null then null else round((headroom_score*0.7+proximity_score*0.3)::numeric,1) end,case when headroom_score is null then 35 else 75 end,jsonb_build_object('headroom_target_mw',10,'distance_zero_score_km',25,'provisional',true),now() from scored
    on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at returning *
  ),sites_upd as (
    update public.lb_sites s set grid_dno=u.dno,nearest_grid_node_id=u.node_id,grid_distance_km=round(u.distance_km::numeric,2),grid_proximity_score=u.proximity_score,grid_score=case when u.headroom_score is null then null else round((u.headroom_score*0.7+u.proximity_score*0.3)::numeric,1) end,grid_score_confidence=case when u.headroom_score is null then 35 else 75 end,updated_at=now() from scored u where s.id=u.site_id returning s.id
  ) select count(*) into v_count from sites_upd;
  perform public.lb_recalculate_site_score(id) from public.lb_sites where nearest_grid_node_id is not null;
  return v_count;
end;$$;

revoke all on public.lb_grid_nodes,public.lb_site_grid_matches from anon,authenticated;
revoke all on function public.lb_refresh_grid_matches(numeric) from public,anon,authenticated;
grant execute on function public.lb_refresh_grid_matches(numeric) to service_role;
