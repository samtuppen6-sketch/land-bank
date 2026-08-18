create or replace function public.lb_refresh_same_dno_grid_proximity_fallback(p_max_km numeric default 50)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ssen integer:=0;v_spen integer:=0;
begin
  with n as (
    select s.id site_id,g.id node_id,st_distance(s.location,g.location)/1000.0 distance_km
    from public.lb_sites s cross join lateral (
      select x.* from public.lb_grid_nodes x where x.dno='SSEN' and x.location is not null and st_dwithin(s.location,x.location,p_max_km*1000) order by s.location <-> x.location limit 1
    ) g where s.dno_licence_operator='Scottish and Southern Electricity Networks' and s.grid_score is null and s.grid_proximity_score is null and s.location is not null
  ) update public.lb_sites s set nearest_grid_node_id=n.node_id,grid_dno='Scottish and Southern Electricity Networks',grid_distance_km=round(n.distance_km::numeric,2),grid_proximity_score=round(greatest(0,least(100,100-(n.distance_km/25.0*100)))::numeric,1),grid_score_confidence=35,updated_at=now() from n where s.id=n.site_id;
  get diagnostics v_ssen=row_count;
  with n as (
    select s.id site_id,g.id node_id,st_distance(s.location,g.location)/1000.0 distance_km
    from public.lb_sites s cross join lateral (
      select x.* from public.lb_grid_nodes x where x.dno='SP Energy Networks' and x.location is not null and st_dwithin(s.location,x.location,p_max_km*1000) order by s.location <-> x.location limit 1
    ) g where s.dno_licence_operator='SP Energy Networks' and s.grid_score is null and s.grid_proximity_score is null and s.location is not null
  ) update public.lb_sites s set nearest_grid_node_id=n.node_id,grid_dno='SP Energy Networks',grid_distance_km=round(n.distance_km::numeric,2),grid_proximity_score=round(greatest(0,least(100,100-(n.distance_km/25.0*100)))::numeric,1),grid_score_confidence=35,updated_at=now() from n where s.id=n.site_id;
  get diagnostics v_spen=row_count;
  return jsonb_build_object('ssen_proximity_fallback',v_ssen,'spen_proximity_fallback',v_spen);
end;$$;
revoke all on function public.lb_refresh_same_dno_grid_proximity_fallback(numeric) from public,anon,authenticated;
grant execute on function public.lb_refresh_same_dno_grid_proximity_fallback(numeric) to service_role;