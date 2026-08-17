insert into public.lb_grid_source_imports(source_name,dno,status,next_offset,page_size,records_imported,resource_id,data_date,source_url)
values('npg_generation_headroom_2026','Northern Powergrid','queued',0,20,0,'npg_ndp_generation_headroom','2026-04-24','https://northernpowergrid.opendatasoft.com/explore/dataset/npg_ndp_generation_headroom/')
on conflict(source_name) do nothing;

create or replace function public.lb_ingest_npg_grid_batch(p_rows jsonb,p_next_offset integer,p_source_total integer,p_complete boolean default false)
returns integer language plpgsql security definer set search_path=public as $$
declare r jsonb;v_count integer:=0;v_total integer:=0;v_source_id text;v_lat double precision;v_lng double precision;v_headroom numeric;v_geom jsonb;v_licence text;v_name text;v_voltage numeric;v_supply numeric;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array';end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_licence:=nullif(r->>'licence_area','');v_name:=nullif(r->>'substation_name','');v_voltage:=nullif(r->>'voltage_kv','')::numeric;v_supply:=nullif(r->>'supply_voltage_kv','')::numeric;v_lat:=nullif(r#>>'{geo_point_2d,lat}','')::double precision;v_lng:=nullif(r#>>'{geo_point_2d,lon}','')::double precision;v_headroom:=nullif(r->>'generation_headroom_capacity_mw_2026','')::numeric;v_geom:=r#>'{geo_shape,geometry}';
    if v_name is null or v_lat is null or v_lng is null then continue;end if;
    v_source_id:=coalesce(v_licence,'NPg')||'|'||public.lb_normalize_grid_name(v_name)||'|'||coalesce(v_voltage::text,'')||'|'||coalesce(v_supply::text,'');
    insert into public.lb_grid_nodes(dno,source_id,name,node_type,voltage_kv,lat,lng,location,generation_headroom_mw,data_date,confidence,source_url,raw_data,updated_at)
    values('Northern Powergrid',v_source_id,v_name,r->>'bulk_supply_point_or_primary',v_voltage,v_lat,v_lng,ST_SetSRID(ST_MakePoint(v_lng,v_lat),4326)::geography,v_headroom,'2026-04-24',92,'https://northernpowergrid.opendatasoft.com/explore/dataset/npg_ndp_generation_headroom/',(r-'geo_shape'),now())
    on conflict(dno,source_id) do update set name=excluded.name,node_type=excluded.node_type,voltage_kv=excluded.voltage_kv,lat=excluded.lat,lng=excluded.lng,location=excluded.location,generation_headroom_mw=excluded.generation_headroom_mw,data_date=excluded.data_date,confidence=excluded.confidence,source_url=excluded.source_url,raw_data=excluded.raw_data,updated_at=now();
    if v_geom is not null and v_geom<>'null'::jsonb then insert into public.lb_grid_supply_areas(dno,licence_area,area_id,primary_name,bsp_name,gsp_name,geometry,source_url,data_date,raw_data,updated_at)
      values('Northern Powergrid',v_licence,v_source_id,v_name,r->>'bsp_group',r->>'gsp_group',ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(v_geom::text),4326)),'https://northernpowergrid.opendatasoft.com/explore/dataset/npg_ndp_generation_headroom/','2026-04-24',(r-'geo_shape'),now())
      on conflict(dno,area_id) do update set licence_area=excluded.licence_area,primary_name=excluded.primary_name,bsp_name=excluded.bsp_name,gsp_name=excluded.gsp_name,geometry=excluded.geometry,source_url=excluded.source_url,data_date=excluded.data_date,raw_data=excluded.raw_data,updated_at=now();end if;
    v_count:=v_count+1;
  end loop;
  select count(*) into v_total from public.lb_grid_nodes where dno='Northern Powergrid';
  update public.lb_grid_source_imports set status=case when p_complete then 'completed' else 'importing' end,next_offset=p_next_offset,records_imported=v_total,source_total=p_source_total,started_at=coalesce(started_at,now()),completed_at=case when p_complete then now() else completed_at end,updated_at=now(),last_error=null where source_name='npg_generation_headroom_2026';return v_count;
end;$$;

create or replace function public.lb_refresh_npg_grid_matches()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sites integer:=0;begin
  with m as (select distinct on(s.id) s.id site_id,a.area_id,g.id grid_node_id,g.generation_headroom_mw,ST_Distance(s.location,g.location)/1000.0 distance_km from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='Northern Powergrid' and s.lat is not null and s.lng is not null and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326)) join public.lb_grid_nodes g on g.dno='Northern Powergrid' and g.source_id=a.area_id order by s.id,a.area_id),
  u as (insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at) select site_id,grid_node_id,round(distance_km::numeric,2),round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1),round(greatest(0,least(100,(generation_headroom_mw/10.0)*100))::numeric,1),round((greatest(0,least(100,(generation_headroom_mw/10.0)*100))*0.75+greatest(0,least(100,100-(distance_km/25.0*100)))*0.25)::numeric,1),94,jsonb_build_object('method','Northern Powergrid published supply-area polygon + 2026 generation headroom','headroom_target_mw',10,'source_date','2026-04-24'),now() from m on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at returning *),
  su as (update public.lb_sites s set grid_dno='Northern Powergrid',nearest_grid_node_id=u.grid_node_id,grid_distance_km=u.distance_km,grid_proximity_score=u.proximity_score,grid_score=u.grid_score,grid_score_confidence=u.score_confidence,updated_at=now() from u where s.id=u.site_id returning s.id)
  select count(*) into v_sites from su;perform public.lb_recalculate_site_score(id) from public.lb_sites where grid_dno='Northern Powergrid';return jsonb_build_object('matched_sites',v_sites);
end;$$;

revoke all on function public.lb_ingest_npg_grid_batch(jsonb,integer,integer,boolean) from public,anon,authenticated;
revoke all on function public.lb_refresh_npg_grid_matches() from public,anon,authenticated;
grant execute on function public.lb_ingest_npg_grid_batch(jsonb,integer,integer,boolean) to service_role;
grant execute on function public.lb_refresh_npg_grid_matches() to service_role;
