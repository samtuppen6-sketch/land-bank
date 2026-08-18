create table if not exists public.lb_grid_area_imports (
  source_name text primary key,
  dno text not null,
  licence_area text not null,
  resource_id text not null,
  status text not null default 'queued' check(status in ('queued','importing','completed','failed')),
  next_offset integer not null default 0,
  page_size integer not null default 10,
  records_imported integer not null default 0,
  source_total integer,
  source_url text,
  attempts integer not null default 0,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);
insert into public.lb_grid_area_imports(source_name,dno,licence_area,resource_id,page_size,source_url)
values('ssen_sepd_primary_areas_2025','SSEN','SEPD','ecc5e138-5dc8-4f24-a46f-b59979052485',10,'https://data.ssen.co.uk/@ssen-distribution/primary-substation-boundaries')
on conflict(source_name) do nothing;

create or replace function public.lb_ingest_ssen_supply_rows(p_rows jsonb,p_next_offset integer,p_source_total integer,p_complete boolean default false)
returns integer language plpgsql security definer set search_path=public as $$
declare r jsonb;v_id text;v_wkt text;v_count integer:=0;v_total integer:=0;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array';end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_id:=coalesce(nullif(r->>'PRIMARY_NRN_SPLIT',''),nullif(r->>'PRIMARY_NAME_2025',''));v_wkt:=nullif(r->>'geometry','');
    if v_id is null or v_wkt is null then continue;end if;
    insert into public.lb_grid_supply_areas(dno,licence_area,area_id,primary_name,primary_alias,bsp_name,gsp_name,geometry,source_url,data_date,raw_data,updated_at)
    values('SSEN','SEPD',v_id,r->>'PRIMARY_NAME_2025',r->>'PRIMARY_NRN_SPLIT',coalesce(r->>'BSP_NAME',r->>'BSP 1'),r->>'GSP_NAME',ST_MakeValid(ST_SetSRID(ST_GeomFromText(v_wkt),4326)),'https://data.ssen.co.uk/@ssen-distribution/primary-substation-boundaries','2025-12-23',r-'geometry',now())
    on conflict(dno,area_id) do update set licence_area=excluded.licence_area,primary_name=excluded.primary_name,primary_alias=excluded.primary_alias,bsp_name=excluded.bsp_name,gsp_name=excluded.gsp_name,geometry=excluded.geometry,source_url=excluded.source_url,data_date=excluded.data_date,raw_data=excluded.raw_data,updated_at=now();v_count:=v_count+1;
  end loop;
  select count(*) into v_total from public.lb_grid_supply_areas where dno='SSEN' and licence_area='SEPD';
  update public.lb_grid_area_imports set status=case when p_complete then 'completed' else 'importing' end,next_offset=p_next_offset,records_imported=v_total,source_total=p_source_total,started_at=coalesce(started_at,now()),completed_at=case when p_complete then now() else completed_at end,updated_at=now(),last_error=null where source_name='ssen_sepd_primary_areas_2025';
  return v_count;
end;$$;
revoke all on public.lb_grid_area_imports from anon,authenticated;
revoke all on function public.lb_ingest_ssen_supply_rows(jsonb,integer,integer,boolean) from public,anon,authenticated;
grant execute on function public.lb_ingest_ssen_supply_rows(jsonb,integer,integer,boolean) to service_role;
