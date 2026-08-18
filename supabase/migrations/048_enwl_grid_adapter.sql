create or replace function public.lb_refresh_enwl_grid_source()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_http record; v_json jsonb; v_nodes integer:=0; v_sites integer:=0;
begin
  select * into v_http from extensions.http_get('https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/extract-enwl-headroom-workbook');
  if v_http.status<>200 then raise exception 'ENWL extractor HTTP %',v_http.status; end if;
  v_json:=v_http.content::jsonb;
  if v_json ? 'error' then raise exception 'ENWL extractor: %',v_json->>'error'; end if;

  insert into public.lb_grid_nodes(dno,source_id,name,node_type,lat,lng,location,generation_headroom_mw,data_date,confidence,source_url,raw_data,updated_at)
  select 'Electricity North West',
         'ENWL_PRIMARY_'||md5(upper(coalesce(x->>'primary_substation',''))||'|'||coalesce(x->>'easting','')||'|'||coalesce(x->>'northing','')),
         x->>'primary_substation','Primary',
         st_y(st_transform(st_setsrid(st_makepoint((x->>'easting')::double precision,(x->>'northing')::double precision),27700),4326)),
         st_x(st_transform(st_setsrid(st_makepoint((x->>'easting')::double precision,(x->>'northing')::double precision),27700),4326)),
         st_transform(st_setsrid(st_makepoint((x->>'easting')::double precision,(x->>'northing')::double precision),27700),4326)::geography,
         nullif(x->>'generation_headroom_inverter_mw','')::numeric,
         '2025-04-01'::date,70,
         v_json->>'source_url',
         x||jsonb_build_object('report_period',v_json->>'report_period','forecast_year',v_json->>'forecast_year','scenario',v_json->>'scenario','technology',v_json->>'technology','metric',v_json->>'metric','source',v_json->>'source'),now()
  from jsonb_array_elements(v_json->'rows') x
  where x->>'primary_substation' is not null and x->>'easting' is not null and x->>'northing' is not null
  on conflict(dno,source_id) do update set name=excluded.name,node_type=excluded.node_type,lat=excluded.lat,lng=excluded.lng,location=excluded.location,generation_headroom_mw=excluded.generation_headroom_mw,data_date=excluded.data_date,confidence=excluded.confidence,source_url=excluded.source_url,raw_data=excluded.raw_data,updated_at=now();
  get diagnostics v_nodes=row_count;

  with nearest as (
    select s.id site_id,n.id node_id,n.generation_headroom_mw,n.confidence,st_distance(s.location,n.location)/1000.0 distance_km
    from public.lb_sites s
    cross join lateral (
      select g.* from public.lb_grid_nodes g
      where g.dno='Electricity North West' and g.location is not null and s.location is not null and st_dwithin(s.location,g.location,40000)
      order by s.location <-> g.location limit 1
    ) n
    where s.location is not null and s.dno_licence_operator='Electricity North West'
  ), scored as (
    select *,round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1) proximity_score,
      case when generation_headroom_mw is null then null else round(greatest(0,least(100,(generation_headroom_mw/10.0)*100))::numeric,1) end headroom_score
    from nearest
  ), upserted as (
    insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
    select site_id,node_id,round(distance_km::numeric,2),proximity_score,headroom_score,
      case when headroom_score is null then null else round((headroom_score*.7+proximity_score*.3)::numeric,1) end,
      case when headroom_score is null then 30 else 70 end,
      jsonb_build_object('source','SP Electricity North West Network Headroom Report April 2025','forecast_year',2026,'technology','Inverter Based','scenario','Best View','headroom_target_mw',10,'distance_zero_score_km',25,'dated_evidence',true),now()
    from scored
    on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at
    returning site_id
  )
  update public.lb_sites s set grid_dno='Electricity North West',nearest_grid_node_id=sc.node_id,grid_distance_km=round(sc.distance_km::numeric,2),grid_proximity_score=sc.proximity_score,
    grid_score=case when sc.headroom_score is null then null else round((sc.headroom_score*.7+sc.proximity_score*.3)::numeric,1) end,
    grid_score_confidence=case when sc.headroom_score is null then 30 else 70 end,updated_at=now()
  from scored sc where s.id=sc.site_id;
  get diagnostics v_sites=row_count;
  perform public.lb_recalculate_site_score(s.id) from public.lb_sites s where s.dno_licence_operator='Electricity North West' and s.nearest_grid_node_id is not null;
  return jsonb_build_object('source_records',v_json->>'record_count','nodes_upserted',v_nodes,'sites_matched',v_sites,'forecast_year',2026,'technology','Inverter Based','source_period','April 2025');
end;$$;

revoke all on function public.lb_refresh_enwl_grid_source() from public,anon,authenticated;
grant execute on function public.lb_refresh_enwl_grid_source() to service_role;