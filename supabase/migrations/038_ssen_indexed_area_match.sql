create or replace function public.lb_refresh_ssen_area_grid_matches()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_area_sites integer:=0;v_matched integer:=0;
begin
  select count(distinct s.id) into v_area_sites
  from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='SSEN'
    and s.location_geom is not null and s.location_geom && a.geometry and ST_Intersects(a.geometry,s.location_geom);

  insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
  select site_id,grid_node_id,round(distance_km::numeric,2),
    round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1),
    case when generation_headroom_mw is null then null else round(greatest(0,least(100,(generation_headroom_mw/10.0)*100))::numeric,1) end,
    case when generation_headroom_mw is null then null else round((greatest(0,least(100,(generation_headroom_mw/10.0)*100))*0.75+greatest(0,least(100,100-(distance_km/25.0*100)))*0.25)::numeric,1) end,
    case when generation_headroom_mw is null then 55 else 92 end,
    jsonb_build_object('method','SSEN published primary supply-area + controlled Primary suffix normalization + generation headroom','headroom_target_mw',10,'source_date','2026-03-11'),now()
  from (
    select distinct on(s.id) s.id site_id,g.id grid_node_id,ST_Distance(s.location,g.location)/1000.0 distance_km,g.generation_headroom_mw
    from public.lb_sites s
    join public.lb_grid_supply_areas a on a.dno='SSEN' and s.location_geom is not null and s.location_geom && a.geometry and ST_Intersects(a.geometry,s.location_geom)
    join public.lb_grid_nodes g on g.dno='SSEN' and g.node_type='Primary'
      and regexp_replace(public.lb_normalize_grid_name(g.name),'(local)?primary$','','g')=public.lb_normalize_grid_name(a.primary_name)
    where g.location is not null
    order by s.id,ST_Distance(s.location,g.location)
  ) m
  on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at;

  update public.lb_sites s
  set grid_dno='SSEN',nearest_grid_node_id=m.grid_node_id,grid_distance_km=m.distance_km,grid_proximity_score=m.proximity_score,grid_score=m.grid_score,grid_score_confidence=m.score_confidence,updated_at=now()
  from public.lb_site_grid_matches m join public.lb_grid_nodes g on g.id=m.grid_node_id and g.dno='SSEN'
  where s.id=m.site_id;
  get diagnostics v_matched=row_count;

  perform public.lb_recalculate_site_score(s.id) from public.lb_sites s where s.grid_dno='SSEN';
  return jsonb_build_object('sites_in_ssen_supply_areas',v_area_sites,'matched_sites',v_matched,'unmatched_sites',greatest(0,v_area_sites-v_matched));
end;$$;
