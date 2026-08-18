insert into public.lb_grid_source_imports(source_name,dno,status,next_offset,page_size,records_imported,resource_id,data_date,source_url)
values('spen_spm_headroom_2026_27','SP Energy Networks','queued',0,500,0,'spm-nshr-data-workbook','2026-06-15','https://spenergynetworks.opendatasoft.com/explore/dataset/spm-nshr-data-workbook/')
on conflict(source_name) do nothing;

insert into public.lb_grid_area_imports(source_name,dno,licence_area,resource_id,status,next_offset,page_size,records_imported,source_url)
values('spen_spm_primary_areas_2026','SP Energy Networks','SPM','spm-dfes-substation-polygons-pss','queued',0,10,0,'https://spenergynetworks.opendatasoft.com/explore/dataset/spm-dfes-substation-polygons-pss/')
on conflict(source_name) do nothing;

create or replace function public.lb_ingest_spen_spm_headroom(p_rows jsonb,p_source_total integer)
returns integer language plpgsql security definer set search_path=public as $$
declare r jsonb;v_group text;v_source_id text;v_headroom numeric;v_voltage numeric;v_count integer:=0;v_total integer:=0;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array';end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_group:=nullif(r->>'headroom_group','');if v_group is null then continue;end if;
    begin v_headroom:=nullif(r->>'fully_converted_headroom_mw_2026_27','')::numeric;exception when others then v_headroom:=null;end;
    begin v_voltage:=nullif(r->>'voltage_kv','')::numeric;exception when others then v_voltage:=null;end;
    v_source_id:='SPM|'||public.lb_normalize_grid_name(v_group)||'|'||coalesce(v_voltage::text,'');
    insert into public.lb_grid_nodes(dno,source_id,name,node_type,voltage_kv,generation_headroom_mw,data_date,confidence,source_url,raw_data,updated_at)
    values('SP Energy Networks',v_source_id,v_group,'Primary Group',v_voltage,v_headroom,'2026-06-15',case when coalesce((r->>'subject_to_upstream_constraints')::boolean,false) then 75 else 92 end,'https://spenergynetworks.opendatasoft.com/explore/dataset/spm-nshr-data-workbook/',r,now())
    on conflict(dno,source_id) do update set name=excluded.name,node_type=excluded.node_type,voltage_kv=excluded.voltage_kv,generation_headroom_mw=excluded.generation_headroom_mw,data_date=excluded.data_date,confidence=excluded.confidence,source_url=excluded.source_url,raw_data=excluded.raw_data,updated_at=now();
    v_count:=v_count+1;
  end loop;
  select count(*) into v_total from public.lb_grid_nodes where dno='SP Energy Networks';
  update public.lb_grid_source_imports set status='completed',next_offset=p_source_total,records_imported=v_total,source_total=p_source_total,started_at=coalesce(started_at,now()),completed_at=now(),updated_at=now(),last_error=null where source_name='spen_spm_headroom_2026_27';
  return v_count;
end;$$;

create or replace function public.lb_ingest_spen_spm_area_rows(p_rows jsonb,p_next_offset integer,p_source_total integer,p_complete boolean default false)
returns integer language plpgsql security definer set search_path=public as $$
declare r jsonb;v_group text;v_geom jsonb;v_lat double precision;v_lng double precision;v_area_id text;v_count integer:=0;v_total integer:=0;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array';end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_group:=nullif(r->>'primary_su','');v_geom:=r#>'{geo_shape,geometry}';v_lat:=nullif(r#>>'{geo_point_2d,lat}','')::double precision;v_lng:=nullif(r#>>'{geo_point_2d,lon}','')::double precision;
    if v_group is null or v_geom is null or v_geom='null'::jsonb then continue;end if;v_area_id:='SPM|'||public.lb_normalize_grid_name(v_group);
    insert into public.lb_grid_supply_areas(dno,licence_area,area_id,primary_name,bsp_name,gsp_name,geometry,source_url,data_date,raw_data,updated_at)
    values('SP Energy Networks','SPM',v_area_id,v_group,r->>'grid_group',r->>'gsp',ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(v_geom::text),4326)),'https://spenergynetworks.opendatasoft.com/explore/dataset/spm-dfes-substation-polygons-pss/','2026-05-20',r-'geo_shape',now())
    on conflict(dno,area_id) do update set licence_area=excluded.licence_area,primary_name=excluded.primary_name,bsp_name=excluded.bsp_name,gsp_name=excluded.gsp_name,geometry=excluded.geometry,source_url=excluded.source_url,data_date=excluded.data_date,raw_data=excluded.raw_data,updated_at=now();
    if v_lat is not null and v_lng is not null then update public.lb_grid_nodes g set lat=v_lat,lng=v_lng,location=ST_SetSRID(ST_MakePoint(v_lng,v_lat),4326)::geography,updated_at=now() where g.dno='SP Energy Networks' and public.lb_normalize_grid_name(g.name)=public.lb_normalize_grid_name(v_group);end if;
    v_count:=v_count+1;
  end loop;
  select count(*) into v_total from public.lb_grid_supply_areas where dno='SP Energy Networks' and licence_area='SPM';
  update public.lb_grid_area_imports set status=case when p_complete then 'completed' else 'importing' end,next_offset=p_next_offset,records_imported=v_total,source_total=p_source_total,started_at=coalesce(started_at,now()),completed_at=case when p_complete then now() else completed_at end,updated_at=now(),last_error=null where source_name='spen_spm_primary_areas_2026';return v_count;
end;$$;

create or replace function public.lb_refresh_spen_spm_grid_matches()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sites integer:=0;
begin
  with m as (
    select distinct on(s.id) s.id site_id,a.area_id,g.id grid_node_id,g.generation_headroom_mw,g.confidence,coalesce((g.raw_data->>'subject_to_upstream_constraints')::boolean,false) upstream_constrained,ST_Distance(s.location,g.location)/1000.0 distance_km
    from public.lb_sites s join public.lb_grid_supply_areas a on a.dno='SP Energy Networks' and a.licence_area='SPM' and s.lat is not null and s.lng is not null and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326))
    join public.lb_grid_nodes g on g.dno='SP Energy Networks' and public.lb_normalize_grid_name(g.name)=public.lb_normalize_grid_name(a.primary_name) where g.location is not null order by s.id,a.area_id
  ),sc as (
    select *,round(greatest(0,least(100,100-(distance_km/25.0*100)))::numeric,1) proximity_score,case when generation_headroom_mw is null then null else round(greatest(0,least(100,(generation_headroom_mw/10.0)*100))::numeric,1) end headroom_score from m
  ),u as (
    insert into public.lb_site_grid_matches(site_id,grid_node_id,distance_km,proximity_score,headroom_score,grid_score,score_confidence,assumptions,matched_at)
    select site_id,grid_node_id,round(distance_km::numeric,2),proximity_score,headroom_score,case when headroom_score is null then null else round(((headroom_score*0.75+proximity_score*0.25)*case when upstream_constrained then 0.85 else 1 end)::numeric,1) end,case when upstream_constrained then 75 else 92 end,jsonb_build_object('method','SPEN SPM published primary polygon + Baseline Fully Converted 2026/27 headroom','headroom_target_mw',10,'upstream_constraint_flag',upstream_constrained,'upstream_constraint_discount',case when upstream_constrained then 0.85 else 1 end,'headroom_workbook_modified','2026-06-15','polygon_modified','2026-05-20'),now() from sc
    on conflict(site_id) do update set grid_node_id=excluded.grid_node_id,distance_km=excluded.distance_km,proximity_score=excluded.proximity_score,headroom_score=excluded.headroom_score,grid_score=excluded.grid_score,score_confidence=excluded.score_confidence,assumptions=excluded.assumptions,matched_at=excluded.matched_at returning *
  ),su as (
    update public.lb_sites s set grid_dno='SP Energy Networks',nearest_grid_node_id=u.grid_node_id,grid_distance_km=u.distance_km,grid_proximity_score=u.proximity_score,grid_score=u.grid_score,grid_score_confidence=u.score_confidence,updated_at=now() from u where s.id=u.site_id returning s.id
  ) select count(*) into v_sites from su;
  perform public.lb_recalculate_site_score(id) from public.lb_sites where grid_dno='SP Energy Networks';return jsonb_build_object('matched_sites',v_sites);
end;$$;

revoke all on function public.lb_ingest_spen_spm_headroom(jsonb,integer) from public,anon,authenticated;
revoke all on function public.lb_ingest_spen_spm_area_rows(jsonb,integer,integer,boolean) from public,anon,authenticated;
revoke all on function public.lb_refresh_spen_spm_grid_matches() from public,anon,authenticated;
grant execute on function public.lb_ingest_spen_spm_headroom(jsonb,integer) to service_role;
grant execute on function public.lb_ingest_spen_spm_area_rows(jsonb,integer,integer,boolean) to service_role;
grant execute on function public.lb_refresh_spen_spm_grid_matches() to service_role;
