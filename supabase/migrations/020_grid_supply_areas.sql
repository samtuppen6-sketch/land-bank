create table if not exists public.lb_grid_supply_areas (
  id uuid primary key default gen_random_uuid(),
  dno text not null,
  licence_area text,
  area_id text not null,
  primary_name text,
  primary_alias text,
  bsp_name text,
  gsp_name text,
  geometry geometry(Geometry,4326) not null,
  source_url text,
  data_date date,
  raw_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(dno,area_id)
);
create index if not exists lb_grid_supply_areas_geom_gix on public.lb_grid_supply_areas using gist(geometry);
create index if not exists lb_grid_supply_areas_dno_idx on public.lb_grid_supply_areas(dno,licence_area);

create or replace function public.lb_normalize_grid_name(p_name text)
returns text language sql immutable as $$ select regexp_replace(lower(coalesce(p_name,'')),'[^a-z0-9]+','','g') $$;

create or replace function public.lb_ingest_ssen_supply_features(p_features jsonb,p_licence_area text,p_source_url text)
returns integer language plpgsql security definer set search_path=public as $$
declare f jsonb;props jsonb;geom jsonb;v_id text;v_count integer:=0;
begin
  if jsonb_typeof(p_features)<>'array' then raise exception 'p_features must be a JSON array';end if;
  for f in select value from jsonb_array_elements(p_features) loop
    props:=coalesce(f->'properties','{}'::jsonb);geom:=f->'geometry';v_id:=coalesce(nullif(props->>'PRIMARY_NRN_SPLIT',''),nullif(props->>'PRIMARY_NAME_2025',''),nullif(props->>'PRIMARY_NAME',''));
    if v_id is null or geom is null or geom='null'::jsonb then continue;end if;
    insert into public.lb_grid_supply_areas(dno,licence_area,area_id,primary_name,primary_alias,bsp_name,gsp_name,geometry,source_url,data_date,raw_data,updated_at)
    values('SSEN',p_licence_area,v_id,coalesce(props->>'PRIMARY_NAME_2025',props->>'PRIMARY_NAME'),coalesce(props->>'PRIMARY_ALIAS',props->>'PRIMARY_NRN_SPLIT'),coalesce(props->>'BSP_NAME',props->>'BSP 1'),props->>'GSP_NAME',ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(geom::text),4326)),p_source_url,'2025-12-23',props,now())
    on conflict(dno,area_id) do update set licence_area=excluded.licence_area,primary_name=excluded.primary_name,primary_alias=excluded.primary_alias,bsp_name=excluded.bsp_name,gsp_name=excluded.gsp_name,geometry=excluded.geometry,source_url=excluded.source_url,data_date=excluded.data_date,raw_data=excluded.raw_data,updated_at=now();v_count:=v_count+1;
  end loop;return v_count;
end;$$;

create or replace function public.lb_refresh_ssen_area_grid_matches()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_area_sites integer:=0;v_exact integer:=0;v_near integer:=0;
begin
  with area_match as (select distinct on(s.id) s.id site_id,a.id area_id,a.primary_name,a.licence_area from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='SSEN' and s.lat is not null and s.lng is not null and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326)) order by s.id,a.id) select count(*) into v_area_sites from area_match;
  with area_match as (select distinct on(s.id) s.id site_id,s.location,a.primary_name,a.licence_area from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='SSEN' and s.lat is not null and s.lng is not null and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326)) order by s.id,a.id),
  exact_match as (select am.site_id,am.licence_area,g.id grid_node_id,ST_Distance(am.location,g.location)/1000.0 distance_km,g.generation_headroom_mw from area_match am join public.lb_grid_nodes g on g.dno='SSEN' and g.node_type='Primary' and public.lb_normalize_grid_name(g.name)=public.lb_normalize_grid_name(am.primary_name)),
  upserted as (insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
  select e.site_id,e.grid_node_id,round(e.distance_km::numeric,2),round(greatest(0,least(100,100-(e.distance_km/25.0*100)))::numeric,1),case when e.generation_headroom_mw is null then null else round(greatest(0,least(100,(e.generation_headroom_mw/10.0)*100))::numeric,1) end,case when e.generation_headroom_mw is null then null else round((greatest(0,least(100,(e.generation_headroom_mw/10.0)*100))*0.75+greatest(0,least(100,100-(e.distance_km/25.0*100)))*0.25)::numeric,1) end,case when e.generation_headroom_mw is null then 55 else 92 end,jsonb_build_object('method','SSEN primary supply-area + normalized primary name','headroom_target_mw',10,'distance_zero_score_km',25,'source_date','2026-03-11'),now() from exact_match e
  on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at returning site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence),
  sites_upd as (update public.lb_sites s set grid_dno='SSEN',nearest_grid_node_id=u.grid_node_id,grid_distance_km=u.distance_km,grid_proximity_score=u.proximity_score,grid_score=u.grid_score,grid_score_confidence=u.score_confidence,updated_at=now() from upserted u where s.id=u.site_id returning s.id)
  select count(*) into v_exact from sites_upd;
  perform public.lb_recalculate_site_score(id) from public.lb_sites where grid_dno='SSEN';return jsonb_build_object('sites_in_ssen_supply_areas',v_area_sites,'exact_primary_matches',v_exact,'nearest_fallback_matches',v_near);
end;$$;

revoke all on public.lb_grid_supply_areas from anon,authenticated;
revoke all on function public.lb_ingest_ssen_supply_features(jsonb,text,text) from public,anon,authenticated;
revoke all on function public.lb_refresh_ssen_area_grid_matches() from public,anon,authenticated;
grant execute on function public.lb_ingest_ssen_supply_features(jsonb,text,text) to service_role;
grant execute on function public.lb_refresh_ssen_area_grid_matches() to service_role;
