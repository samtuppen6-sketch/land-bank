create table if not exists public.lb_grid_source_imports (
  source_name text primary key,
  dno text not null,
  status text not null default 'queued' check(status in ('queued','importing','completed','failed')),
  resource_id text,
  next_offset integer not null default 0,
  page_size integer not null default 250,
  records_imported integer not null default 0,
  source_total integer,
  data_date date,
  source_url text,
  attempts integer not null default 0,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

insert into public.lb_grid_source_imports(source_name,dno,resource_id,page_size,data_date,source_url)
values('ssen_headroom_march_2026','SSEN','52e9a305-ad90-4c81-9175-20a40ef57894',250,'2026-03-11','https://data.ssen.co.uk/@ssen-distribution/generation-availability-and-network-capacity')
on conflict(source_name) do update set resource_id=excluded.resource_id,data_date=excluded.data_date,source_url=excluded.source_url;

create or replace function public.lb_ingest_ssen_grid_batch(p_rows jsonb,p_next_offset integer,p_source_total integer,p_complete boolean default false)
returns integer language plpgsql security definer set search_path=public as $$
declare r jsonb;v_count integer:=0;v_total integer:=0;v_lat double precision;v_lng double precision;v_headroom numeric;v_demand_headroom numeric;v_voltage numeric;v_source_id text;v_rag text;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array';end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_source_id:=nullif(r->>'AssetID','');v_lat:=nullif(r->>'Location Latitude','')::double precision;v_lng:=nullif(r->>'Location Longitude','')::double precision;
    if v_source_id is null or v_lat is null or v_lng is null then continue;end if;
    begin v_headroom:=nullif(regexp_replace(coalesce(r->>'estimated_generation_headroom__mw_',''),'[^0-9.\-]','','g'),'')::numeric;exception when others then v_headroom:=null;end;
    begin v_demand_headroom:=nullif(regexp_replace(coalesce(r->>'estimated_demand_headroom__mva_',''),'[^0-9.\-]','','g'),'')::numeric;exception when others then v_demand_headroom:=null;end;
    begin v_voltage:=nullif((regexp_match(coalesce(r->>'voltage__kv_',''),'([0-9]+(?:\.[0-9]+)?)'))[1],'')::numeric;exception when others then v_voltage:=null;end;
    v_rag:=nullif(r->>'Substation Generation RAG Status','');
    insert into public.lb_grid_nodes(dno,source_id,name,node_type,voltage_kv,lat,lng,location,generation_headroom_mw,demand_headroom_mw,connected_generation_mw,accepted_generation_mw,data_date,confidence,source_url,raw_data,updated_at)
    values('SSEN',v_source_id,r->>'Substation',r->>'Substation Type',v_voltage,v_lat,v_lng,ST_SetSRID(ST_MakePoint(v_lng,v_lat),4326)::geography,v_headroom,v_demand_headroom,nullif(r->>'connected_generation__mw_','')::numeric,nullif(r->>'contracted_generation__mw_','')::numeric,'2026-03-11',case when v_headroom is not null then 90 when v_rag is not null then 60 else 45 end,'https://data.ssen.co.uk/@ssen-distribution/generation-availability-and-network-capacity',r,now())
    on conflict(dno,source_id) do update set name=excluded.name,node_type=excluded.node_type,voltage_kv=excluded.voltage_kv,lat=excluded.lat,lng=excluded.lng,location=excluded.location,generation_headroom_mw=excluded.generation_headroom_mw,demand_headroom_mw=excluded.demand_headroom_mw,connected_generation_mw=excluded.connected_generation_mw,accepted_generation_mw=excluded.accepted_generation_mw,data_date=excluded.data_date,confidence=excluded.confidence,source_url=excluded.source_url,raw_data=excluded.raw_data,updated_at=now();
    v_count:=v_count+1;
  end loop;
  select count(*) into v_total from public.lb_grid_nodes where dno='SSEN';
  update public.lb_grid_source_imports set status=case when p_complete then 'completed' else 'importing' end,next_offset=p_next_offset,records_imported=v_total,source_total=p_source_total,started_at=coalesce(started_at,now()),completed_at=case when p_complete then now() else completed_at end,updated_at=now(),last_error=null where source_name='ssen_headroom_march_2026';
  return v_count;
end;$$;

revoke all on public.lb_grid_source_imports from anon,authenticated;
revoke all on function public.lb_ingest_ssen_grid_batch(jsonb,integer,integer,boolean) from public,anon,authenticated;
grant execute on function public.lb_ingest_ssen_grid_batch(jsonb,integer,integer,boolean) to service_role;
