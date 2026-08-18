create or replace function public.lb_refresh_ukpn_grid_source()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare j_epn jsonb; j_spn jsonb; j_lpn jsonb; v_nodes integer:=0; v_sites integer:=0;
begin
  select content::jsonb into j_epn from extensions.http_get('https://ukpowernetworks.opendatasoft.com/api/explore/v2.1/catalog/datasets/ukpn-capacity-heatmap/attachments/ltds_heatmap_epn_2026_01_json_2026_05_29_v10json');
  select content::jsonb into j_spn from extensions.http_get('https://ukpowernetworks.opendatasoft.com/api/explore/v2.1/catalog/datasets/ukpn-capacity-heatmap/attachments/ltds_heatmap_spn_2026_01_json_2026_05_29_v10json');
  select content::jsonb into j_lpn from extensions.http_get('https://ukpowernetworks.opendatasoft.com/api/explore/v2.1/catalog/datasets/ukpn-capacity-heatmap/attachments/ltds_heatmap_lpn_2026_01_json_2026_05_29_v10json');

  insert into public.lb_grid_nodes(dno,source_id,name,node_type,voltage_kv,lat,lng,location,generation_headroom_mw,firm_capacity_mva,data_date,confidence,source_url,raw_data,updated_at)
  select 'UK Power Networks','UKPN_'||(x->>'mRID'),x->>'name',x->>'type',nullif(x->'voltages'->>0,'')::numeric,
         (x->>'latitude')::double precision,(x->>'longitude')::double precision,
         st_setsrid(st_makepoint((x->>'longitude')::double precision,(x->>'latitude')::double precision),4326)::geography,
         nullif(x->>'generationAvailableCapacity','')::numeric,nullif(x->>'generationFirmCapacity','')::numeric,
         '2026-05-29'::date,90,'https://ukpowernetworks.opendatasoft.com/explore/dataset/ukpn-capacity-heatmap/',
         x||jsonb_build_object('source_title',src_title,'source_date',src_date,'issued',src_issued,'valid',src_valid,'capacity_metric','generationAvailableCapacity'),now()
  from (
    select x,j_epn->>'title' src_title,j_epn->>'date' src_date,j_epn->>'issued' src_issued,j_epn->'valid' src_valid from jsonb_array_elements(j_epn->'Substations') x
    union all select x,j_spn->>'title',j_spn->>'date',j_spn->>'issued',j_spn->'valid' from jsonb_array_elements(j_spn->'Substations') x
    union all select x,j_lpn->>'title',j_lpn->>'date',j_lpn->>'issued',j_lpn->'valid' from jsonb_array_elements(j_lpn->'Substations') x
  ) q
  where x->>'mRID' is not null and x->>'latitude' is not null and x->>'longitude' is not null
  on conflict(dno,source_id) do update set name=excluded.name,node_type=excluded.node_type,voltage_kv=excluded.voltage_kv,lat=excluded.lat,lng=excluded.lng,location=excluded.location,generation_headroom_mw=excluded.generation_headroom_mw,firm_capacity_mva=excluded.firm_capacity_mva,data_date=excluded.data_date,confidence=excluded.confidence,source_url=excluded.source_url,raw_data=excluded.raw_data,updated_at=now();
  get diagnostics v_nodes=row_count;

  with nearest as (
    select s.id site_id,n.id node_id,n.generation_headroom_mw,n.confidence,st_distance(s.location,n.location)/1000.0 distance_km
    from public.lb_sites s
    cross join lateral (
      select g.* from public.lb_grid_nodes g
      where g.dno='UK Power Networks' and g.location is not null and s.location is not null
        and (g.raw_data->>'area')=case s.dno_licence_area when 'East England' then 'EPN' when 'South East England' then 'SPN' when 'London' then 'LPN' end
        and st_dwithin(s.location,g.location,40000)
      order by s.location <-> g.location limit 1
    ) n where s.location is not null and s.dno_licence_operator='UK Power Networks'
  ), scored as (
    select *,round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1) proximity_score,
      case when generation_headroom_mw is null then null else round(greatest(0,least(100,(generation_headroom_mw/10.0)*100))::numeric,1) end headroom_score from nearest
  ), upserted as (
    insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
    select site_id,node_id,round(distance_km::numeric,2),proximity_score,headroom_score,
      case when headroom_score is null then null else round((headroom_score*.7+proximity_score*.3)::numeric,1) end,
      case when headroom_score is null then 40 else 90 end,
      jsonb_build_object('source','UK Power Networks LTDS Capacity Heatmap','issued','2026-05-29','capacity_metric','generationAvailableCapacity','headroom_target_mw',10,'distance_zero_score_km',25,'authoritative_heatmap',true),now()
    from scored
    on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at returning site_id
  )
  update public.lb_sites s set grid_dno='UK Power Networks',nearest_grid_node_id=sc.node_id,grid_distance_km=round(sc.distance_km::numeric,2),grid_proximity_score=sc.proximity_score,
    grid_score=case when sc.headroom_score is null then null else round((sc.headroom_score*.7+sc.proximity_score*.3)::numeric,1) end,
    grid_score_confidence=case when sc.headroom_score is null then 40 else 90 end,updated_at=now()
  from scored sc where s.id=sc.site_id;
  get diagnostics v_sites=row_count;
  perform public.lb_recalculate_site_score(s.id) from public.lb_sites s where s.dno_licence_operator='UK Power Networks' and s.nearest_grid_node_id is not null;
  return jsonb_build_object('nodes_upserted',v_nodes,'sites_matched',v_sites,'epn_records',jsonb_array_length(j_epn->'Substations'),'spn_records',jsonb_array_length(j_spn->'Substations'),'lpn_records',jsonb_array_length(j_lpn->'Substations'),'source_issued','2026-05-29');
end;$$;
revoke all on function public.lb_refresh_ukpn_grid_source() from public,anon,authenticated;
grant execute on function public.lb_refresh_ukpn_grid_source() to service_role;