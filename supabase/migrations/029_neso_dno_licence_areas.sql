create table if not exists public.lb_dno_licence_areas (
  id integer primary key,dno_code text not null,dno_full text,area_name text,geometry geometry(Geometry,4326) not null,source_url text not null,source_date date,raw_properties jsonb not null default '{}'::jsonb,updated_at timestamptz not null default now()
);
create index if not exists lb_dno_licence_areas_geom_gix on public.lb_dno_licence_areas using gist(geometry);
alter table public.lb_sites add column if not exists dno_licence_code text,add column if not exists dno_licence_operator text,add column if not exists dno_licence_area text;

create or replace function public.lb_refresh_neso_dno_boundaries()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare resp extensions.http_response;payload jsonb;f jsonb;props jsonb;geom jsonb;v_count integer:=0;v_sites integer:=0;v_url text:='https://api.neso.energy/dataset/0e377f16-95e9-4c15-a1fc-49e06a39cfa0/resource/1c6a7dc0-1b6c-443a-bc67-5f7125649434/download/gb-dno-license-areas-20240503-as-geojson.geojson';
begin
  resp:=extensions.http_get(v_url);if resp.status<>200 then raise exception 'NESO DNO boundary HTTP %',resp.status;end if;payload:=resp.content::jsonb;
  for f in select value from jsonb_array_elements(coalesce(payload->'features','[]'::jsonb)) loop
    props:=coalesce(f->'properties','{}'::jsonb);geom:=f->'geometry';if props->>'ID' is null or geom is null or geom='null'::jsonb then continue;end if;
    insert into public.lb_dno_licence_areas(id,dno_code,dno_full,area_name,geometry,source_url,source_date,raw_properties,updated_at) values((props->>'ID')::integer,props->>'DNO',props->>'DNO_Full',props->>'Area',ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(geom::text),27700),4326),v_url,'2024-05-03',props,now()) on conflict(id) do update set dno_code=excluded.dno_code,dno_full=excluded.dno_full,area_name=excluded.area_name,geometry=excluded.geometry,source_url=excluded.source_url,source_date=excluded.source_date,raw_properties=excluded.raw_properties,updated_at=now();v_count:=v_count+1;
  end loop;
  with m as (select distinct on(s.id) s.id site_id,a.dno_code,a.dno_full,a.area_name from public.lb_sites s join public.lb_dno_licence_areas a on s.lat is not null and s.lng is not null and ST_Intersects(a.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326)) order by s.id,a.id),u as(update public.lb_sites s set dno_licence_code=m.dno_code,dno_licence_operator=m.dno_full,dno_licence_area=m.area_name,updated_at=now() from m where s.id=m.site_id returning s.id) select count(*) into v_sites from u;
  return jsonb_build_object('boundaries_imported',v_count,'sites_assigned',v_sites);
end;$$;

create or replace view public.lb_grid_coverage_by_dno as
select coalesce(dno_licence_code,'UNASSIGNED') dno_code,coalesce(dno_licence_operator,'Unassigned') dno_operator,coalesce(dno_licence_area,'Unassigned') licence_area,count(*) sites,count(*) filter(where grid_score is not null) grid_scored,round(100.0*count(*) filter(where grid_score is not null)/nullif(count(*),0),1) grid_coverage_pct,count(*) filter(where solar_score is not null) solar_screened,count(*) filter(where flood_score is not null) flood_screened from public.lb_sites group by 1,2,3;
grant select on public.lb_grid_coverage_by_dno to anon,authenticated;
revoke all on public.lb_dno_licence_areas from anon,authenticated;
revoke all on function public.lb_refresh_neso_dno_boundaries() from public,anon,authenticated;
grant execute on function public.lb_refresh_neso_dno_boundaries() to service_role;
