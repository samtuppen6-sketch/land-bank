create or replace function public.lb_ingest_constraint_batch(
  p_dataset text,p_features jsonb,p_next_offset integer,p_complete boolean default false,p_source_url text default null
) returns integer
language plpgsql security definer set search_path=public as $$
declare
  f jsonb;props jsonb;geom jsonb;v_entity bigint;v_reference text;v_name text;v_count integer:=0;v_total integer:=0;
begin
  if jsonb_typeof(p_features)<>'array' then raise exception 'p_features must be a JSON array';end if;
  for f in select value from jsonb_array_elements(p_features) loop
    props:=coalesce(f->'properties','{}'::jsonb);geom:=f->'geometry';v_entity:=nullif(props->>'entity','')::bigint;v_reference:=props->>'reference';v_name:=props->>'name';
    if v_entity is null or geom is null or geom='null'::jsonb then continue;end if;
    insert into public.lb_constraint_features(dataset,entity,reference,name,geometry,properties,source_url,fetched_at)
    values(p_dataset,v_entity,v_reference,v_name,ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(geom::text),4326)),props,p_source_url,now())
    on conflict(dataset,entity) do update set reference=excluded.reference,name=excluded.name,geometry=excluded.geometry,properties=excluded.properties,source_url=excluded.source_url,fetched_at=excluded.fetched_at;
    v_count:=v_count+1;
  end loop;
  select count(*) into v_total from public.lb_constraint_features where dataset=p_dataset;
  insert into public.lb_constraint_imports(dataset,status,next_offset,records_imported,started_at,completed_at,updated_at,last_error)
  values(p_dataset,case when p_complete then 'completed' else 'importing' end,p_next_offset,v_total,now(),case when p_complete then now() else null end,now(),null)
  on conflict(dataset) do update set status=excluded.status,next_offset=excluded.next_offset,records_imported=v_total,started_at=coalesce(public.lb_constraint_imports.started_at,now()),completed_at=case when p_complete then now() else public.lb_constraint_imports.completed_at end,updated_at=now(),last_error=null;
  return v_count;
end;$$;
