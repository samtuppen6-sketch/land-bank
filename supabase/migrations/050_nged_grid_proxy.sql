create or replace function public.lb_ingest_nged_osm_response(p_request_id bigint)
returns jsonb language plpgsql security definer set search_path=public,net as $$
declare v_json jsonb; v_nodes integer:=0; v_region text;
begin
  select content::jsonb into v_json from net._http_response where id=p_request_id and status_code=200;
  if v_json is null then raise exception 'No successful pg_net response %',p_request_id; end if;
  v_region:=v_json->>'region';
  insert into public.lb_grid_nodes(dno,source_id,name,node_type,voltage_kv,lat,lng,location,generation_headroom_mw,data_date,confidence,source_url,raw_data,updated_at)
  select 'NGED open-network proxy','OSM_'||(x->>'osm_type')||'_'||(x->>'osm_id'),x->>'name',coalesce(x->>'substation','substation'),
    case when (regexp_match(coalesce(x->>'voltage',''),'([0-9]{4,6})'))[1] is not null then ((regexp_match(coalesce(x->>'voltage',''),'([0-9]{4,6})'))[1])::numeric/1000.0 else null end,
    (x->>'lat')::double precision,(x->>'lng')::double precision,
    st_setsrid(st_makepoint((x->>'lng')::double precision,(x->>'lat')::double precision),4326)::geography,
    null,current_date,35,'https://www.openstreetmap.org/',
    x||jsonb_build_object('region_query',v_region,'evidence_type','NGED/WPD attributed high-voltage substation proximity proxy','source_extract',v_json->>'source','no_headroom_claim',true),now()
  from jsonb_array_elements(v_json->'rows') x where x->>'lat' is not null and x->>'lng' is not null
  on conflict(dno,source_id) do update set name=excluded.name,node_type=excluded.node_type,voltage_kv=excluded.voltage_kv,lat=excluded.lat,lng=excluded.lng,location=excluded.location,confidence=excluded.confidence,raw_data=excluded.raw_data,updated_at=now();
  get diagnostics v_nodes=row_count;
  return jsonb_build_object('region',v_region,'nodes_upserted',v_nodes,'source_records',v_json->>'record_count');
end;$$;

create or replace function public.lb_refresh_nged_grid_proxy(p_max_km numeric default 40)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sites integer:=0;
begin
  with nearest as (
    select s.id site_id,n.id node_id,st_distance(s.location,n.location)/1000.0 distance_km
    from public.lb_sites s cross join lateral (
      select g.* from public.lb_grid_nodes g where g.dno='NGED open-network proxy' and g.location is not null and s.location is not null and st_dwithin(s.location,g.location,p_max_km*1000)
      order by s.location <-> g.location limit 1
    ) n where s.dno_licence_operator='National Grid Electricity Distribution' and s.location is not null and s.grid_score is null
  ), scored as (select *,round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1) proximity_score from nearest)
  update public.lb_sites s set grid_dno='National Grid Electricity Distribution',nearest_grid_node_id=sc.node_id,grid_distance_km=round(sc.distance_km::numeric,2),grid_proximity_score=sc.proximity_score,grid_score_confidence=35,updated_at=now()
  from scored sc where s.id=sc.site_id;
  get diagnostics v_sites=row_count;
  return jsonb_build_object('proxy_sites_matched',v_sites,'note','Proximity evidence only; grid_score remains null until authoritative headroom/capacity evidence is available');
end;$$;
revoke all on function public.lb_ingest_nged_osm_response(bigint) from public,anon,authenticated;
revoke all on function public.lb_refresh_nged_grid_proxy(numeric) from public,anon,authenticated;
grant execute on function public.lb_ingest_nged_osm_response(bigint) to service_role;
grant execute on function public.lb_refresh_nged_grid_proxy(numeric) to service_role;