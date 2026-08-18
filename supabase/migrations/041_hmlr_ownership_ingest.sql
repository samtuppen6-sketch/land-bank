create table if not exists public.lb_title_imports (
  source_name text primary key,status text not null default 'queued' check(status in ('queued','importing','completed','failed')),source_date date,records_imported integer not null default 0,source_ref text,last_error text,updated_at timestamptz not null default now()
);

create or replace function public.lb_ingest_title_polygon_batch(p_features jsonb,p_source text,p_source_date date default null,p_source_ref text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare f jsonb;props jsonb;geom jsonb;v_inspire text;v_title text;v_tenure text;v_count integer:=0;
begin
  if jsonb_typeof(p_features)<>'array' then raise exception 'p_features must be a JSON array';end if;
  for f in select value from jsonb_array_elements(p_features) loop
    props:=coalesce(f->'properties','{}'::jsonb);geom:=f->'geometry';
    v_inspire:=coalesce(nullif(props->>'INSPIREID',''),nullif(props->>'inspireid',''),nullif(props->>'inspire_id',''),nullif(props->>'inspireId',''));
    v_title:=coalesce(nullif(props->>'TITLE_NO',''),nullif(props->>'title_number',''),nullif(props->>'TitleNumber',''),nullif(props->>'title_no',''));
    v_tenure:=coalesce(nullif(props->>'TENURE',''),nullif(props->>'tenure',''));
    if geom is null or geom='null'::jsonb or (v_inspire is null and v_title is null) then continue;end if;
    insert into public.lb_title_polygons(inspire_id,title_number,tenure,geometry,source_date,source,source_ref,raw_data,updated_at)
    values(v_inspire,v_title,v_tenure,ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(geom::text),4326)),p_source_date,p_source,p_source_ref,props,now())
    on conflict(inspire_id) do update set title_number=coalesce(excluded.title_number,public.lb_title_polygons.title_number),tenure=coalesce(excluded.tenure,public.lb_title_polygons.tenure),geometry=excluded.geometry,source_date=excluded.source_date,source=excluded.source,source_ref=excluded.source_ref,raw_data=excluded.raw_data,updated_at=now();
    v_count:=v_count+1;
  end loop;return v_count;
end;$$;

create or replace function public.lb_ingest_corporate_owner_batch(p_rows jsonb,p_source_date date default null,p_source_ref text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare r jsonb;v_title text;v_company text;v_name text;v_tenure text;v_addr text;v_count integer:=0;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array';end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_title:=coalesce(nullif(r->>'Title Number',''),nullif(r->>'title_number',''),nullif(r->>'TITLE_NO',''));
    v_company:=coalesce(nullif(r->>'Company Registration No. (1)',''),nullif(r->>'company_number',''),nullif(r->>'company_registration_number',''));
    v_name:=coalesce(nullif(r->>'Proprietor Name (1)',''),nullif(r->>'proprietor_name',''));v_tenure:=coalesce(nullif(r->>'Tenure',''),nullif(r->>'tenure',''));v_addr:=coalesce(nullif(r->>'Proprietor Address (1)',''),nullif(r->>'proprietor_address',''));
    if v_title is null or (v_company is null and v_name is null) then continue;end if;
    insert into public.lb_corporate_title_owners(title_number,company_number,proprietor_name,tenure,proprietor_address,source,source_date,raw_data)
    values(v_title,v_company,v_name,v_tenure,v_addr,'HM Land Registry corporate ownership data',p_source_date,r)
    on conflict(title_number,company_number,proprietor_name) do update set tenure=excluded.tenure,proprietor_address=excluded.proprietor_address,source_date=excluded.source_date,raw_data=excluded.raw_data;
    v_count:=v_count+1;
  end loop;return v_count;
end;$$;

create or replace function public.lb_refresh_site_title_matches()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_matches integer:=0;v_exact integer:=0;
begin
  insert into public.lb_site_title_matches(site_id,title_polygon_id,match_method,confidence,matched_at)
  select s.id,t.id,'site_point_intersection',65,now() from public.lb_sites s join public.lb_title_polygons t on s.location_geom is not null and s.location_geom&&t.geometry and ST_Intersects(t.geometry,s.location_geom)
  on conflict(site_id,title_polygon_id) do update set match_method=excluded.match_method,confidence=excluded.confidence,matched_at=excluded.matched_at;get diagnostics v_matches=row_count;

  insert into public.lb_ownership_evidence(site_id,organisation_id,evidence_type,confidence,source,source_ref,details,verified_at)
  select distinct s.id,o.id,'title_company_number_exact',100,'HM Land Registry title + corporate proprietor match',t.title_number,jsonb_build_object('title_number',t.title_number,'inspire_id',t.inspire_id,'company_number',co.company_number,'proprietor_name',co.proprietor_name),now()
  from public.lb_site_title_matches stm join public.lb_sites s on s.id=stm.site_id join public.lb_title_polygons t on t.id=stm.title_polygon_id and t.title_number is not null join public.lb_corporate_title_owners co on co.title_number=t.title_number join public.lb_organisations o on o.company_number=co.company_number and o.id is not null
  on conflict(site_id,organisation_id,evidence_type,source,source_ref) do update set confidence=excluded.confidence,details=excluded.details,verified_at=excluded.verified_at;get diagnostics v_exact=row_count;

  update public.lb_sites s set ownership_score=e.score,updated_at=now() from(select site_id,max(confidence) score from public.lb_ownership_evidence group by site_id)e where s.id=e.site_id;
  perform public.lb_recalculate_site_score(s.id) from public.lb_sites s where exists(select 1 from public.lb_ownership_evidence e where e.site_id=s.id and e.confidence>=85);
  return jsonb_build_object('site_title_matches_written',v_matches,'exact_title_company_evidence_written',v_exact);
end;$$;

revoke all on public.lb_title_imports from anon,authenticated;
revoke all on function public.lb_ingest_title_polygon_batch(jsonb,text,date,text) from public,anon,authenticated;
revoke all on function public.lb_ingest_corporate_owner_batch(jsonb,date,text) from public,anon,authenticated;
revoke all on function public.lb_refresh_site_title_matches() from public,anon,authenticated;
grant execute on function public.lb_ingest_title_polygon_batch(jsonb,text,date,text) to service_role;
grant execute on function public.lb_ingest_corporate_owner_batch(jsonb,date,text) to service_role;
grant execute on function public.lb_refresh_site_title_matches() to service_role;
