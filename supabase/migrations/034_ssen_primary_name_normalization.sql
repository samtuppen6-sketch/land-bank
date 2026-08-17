create or replace function public.lb_refresh_ssen_area_grid_matches()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_area_sites integer:=0;v_matched integer:=0;
begin
  with area_match as (
    select distinct on(s.id) s.id site_id,a.id area_id,a.primary_name
    from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='SSEN'
      and s.lat is not null and s.lng is not null
      and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326))
    order by s.id,a.id
  ) select count(*) into v_area_sites from area_match;

  with area_match as (
    select distinct on(s.id) s.id site_id,s.location,a.primary_name,a.id area_id
    from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='SSEN'
      and s.lat is not null and s.lng is not null
      and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326))
    order by s.id,a.id
  ),m as (
    select am.site_id,g.id grid_node_id,ST_Distance(am.location,g.location)/1000.0 distance_km,g.generation_headroom_mw
    from area_match am join public.lb_grid_nodes g on g.dno='SSEN' and g.node_type='Primary'
      and regexp_replace(public.lb_normalize_grid_name(g.name),'(local)?primary$','','g')=public.lb_normalize_grid_name(am.primary_name)
    where g.location is not null
  ),u as (
    insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
    select site_id,grid_node_id,round(distance_km::numeric,2),round(greatest(0,least(100,100-distance_km/25*100))::numeric,1),
      case when generation_headroom_mw is null then null else round(greatest(0,least(100,generation_headroom_mw/10*100))::numeric,1) end,
      case when generation_headroom_mw is null then null else round((greatest(0,least(100,generation_headroom_mw/10*100))*.75+greatest(0,least(100,100-distance_km/25*100))*.25)::numeric,1) end,
      case when generation_headroom_mw is null then 55 else 92 end,
      jsonb_build_object('method','SSEN published primary supply-area + controlled Primary suffix normalization + generation headroom','headroom_target_mw',10,'source_date','2026-03-11'),now()
    from m on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at returning *
  ),su as (
    update public.lb_sites s set grid_dno='SSEN',nearest_grid_node_id=u.grid_node_id,grid_distance_km=u.distance_km,grid_proximity_score=u.proximity_score,grid_score=u.grid_score,grid_score_confidence=u.score_confidence,updated_at=now() from u where s.id=u.site_id returning s.id
  ) select count(*) into v_matched from su;
  perform public.lb_recalculate_site_score(id) from public.lb_sites where grid_dno='SSEN';
  return jsonb_build_object('sites_in_ssen_supply_areas',v_area_sites,'matched_sites',v_matched,'unmatched_sites',greatest(0,v_area_sites-v_matched));
end;$$;
