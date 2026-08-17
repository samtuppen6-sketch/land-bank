create table if not exists public.lb_constraint_features (
  id uuid primary key default gen_random_uuid(),
  dataset text not null,
  entity bigint not null,
  reference text,
  name text,
  geometry geometry(Geometry,4326) not null,
  properties jsonb not null default '{}'::jsonb,
  source_url text,
  fetched_at timestamptz not null default now(),
  unique(dataset,entity)
);
create index if not exists lb_constraint_features_geom_gix on public.lb_constraint_features using gist(geometry);
create index if not exists lb_constraint_features_dataset_idx on public.lb_constraint_features(dataset);

create table if not exists public.lb_constraint_imports (
  dataset text primary key,
  status text not null default 'queued' check(status in ('queued','importing','completed','failed')),
  next_offset integer not null default 0,
  page_size integer not null default 50,
  records_imported integer not null default 0,
  attempts integer not null default 0,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

insert into public.lb_constraint_imports(dataset,page_size) values
 ('green-belt',50),
 ('site-of-special-scientific-interest',50),
 ('agricultural-land-classification',25),
 ('ancient-woodland',50),
 ('scheduled-monument',50)
on conflict(dataset) do nothing;

create table if not exists public.lb_site_constraints (
  site_id uuid not null references public.lb_sites(id) on delete cascade,
  feature_id uuid not null references public.lb_constraint_features(id) on delete cascade,
  dataset text not null,
  reference text,
  name text,
  penalty numeric not null default 0,
  detected_at timestamptz not null default now(),
  primary key(site_id,feature_id)
);
create index if not exists lb_site_constraints_site_idx on public.lb_site_constraints(site_id);
create index if not exists lb_site_constraints_dataset_idx on public.lb_site_constraints(dataset);

alter table public.lb_sites
  add column if not exists agricultural_grade text,
  add column if not exists agricultural_score numeric,
  add column if not exists topography_score numeric;

create or replace function public.lb_ingest_constraint_batch(p_dataset text,p_features jsonb,p_next_offset integer,p_complete boolean default false,p_source_url text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare f jsonb;props jsonb;geom jsonb;v_entity bigint;v_reference text;v_name text;v_count integer:=0;
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
  insert into public.lb_constraint_imports(dataset,status,next_offset,records_imported,started_at,completed_at,updated_at,last_error)
  values(p_dataset,case when p_complete then 'completed' else 'importing' end,p_next_offset,v_count,now(),case when p_complete then now() else null end,now(),null)
  on conflict(dataset) do update set status=excluded.status,next_offset=excluded.next_offset,records_imported=public.lb_constraint_imports.records_imported+v_count,started_at=coalesce(public.lb_constraint_imports.started_at,now()),completed_at=case when p_complete then now() else public.lb_constraint_imports.completed_at end,updated_at=now(),last_error=null;
  return v_count;
end;$$;

create or replace function public.lb_refresh_constraint_intersections(p_dataset text,p_penalty numeric default 0)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  delete from public.lb_site_constraints where dataset=p_dataset;
  insert into public.lb_site_constraints(site_id,feature_id,dataset,reference,name,penalty,detected_at)
  select s.id,f.id,f.dataset,f.reference,f.name,p_penalty,now() from public.lb_sites s join public.lb_constraint_features f on f.dataset=p_dataset
  where s.lat is not null and s.lng is not null and ST_Intersects(f.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326));
  get diagnostics v_count=row_count;return v_count;
end;$$;

create or replace function public.lb_apply_agricultural_classification()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  if not exists(select 1 from public.lb_constraint_imports where dataset='agricultural-land-classification' and status='completed') then raise exception 'Agricultural Land Classification import is not complete';end if;
  with matches as (
    select s.id site_id,f.reference,
      case when lower(f.reference) like '%grade 1%' then 10 when lower(f.reference) like '%grade 2%' then 20 when lower(f.reference) like '%grade 3a%' then 35 when lower(f.reference) like '%grade 3b%' then 75 when lower(f.reference) like '%grade 4%' then 90 when lower(f.reference) like '%grade 5%' then 100 else 60 end::numeric score,
      row_number() over(partition by s.id order by case when lower(f.reference) like '%grade 1%' then 10 when lower(f.reference) like '%grade 2%' then 20 when lower(f.reference) like '%grade 3a%' then 35 when lower(f.reference) like '%grade 3b%' then 75 when lower(f.reference) like '%grade 4%' then 90 when lower(f.reference) like '%grade 5%' then 100 else 60 end asc) rn
    from public.lb_sites s join public.lb_constraint_features f on f.dataset='agricultural-land-classification'
    where s.lat is not null and s.lng is not null and ST_Intersects(f.geometry,ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326))
  ),upd as(update public.lb_sites s set agricultural_grade=m.reference,agricultural_score=m.score,updated_at=now() from matches m where m.rn=1 and s.id=m.site_id returning s.id)
  select count(*) into v_count from upd;return v_count;
end;$$;

create or replace function public.lb_apply_planning_constraint_scores(p_datasets text[])
returns integer language plpgsql security definer set search_path=public as $$
declare missing text;v_count integer;begin
  select string_agg(d,', ') into missing from unnest(p_datasets) d where not exists(select 1 from public.lb_constraint_imports i where i.dataset=d and i.status='completed');
  if missing is not null then raise exception 'Planning datasets not complete: %',missing;end if;
  with ds as (
    select s.id site_id,d.dataset,coalesce(max(c.penalty),0) penalty from public.lb_sites s cross join unnest(p_datasets) d(dataset) left join public.lb_site_constraints c on c.site_id=s.id and c.dataset=d.dataset group by s.id,d.dataset
  ),scores as(select site_id,greatest(0,100-sum(penalty))::numeric score from ds group by site_id),upd as(update public.lb_sites s set planning_score=sc.score,updated_at=now() from scores sc where s.id=sc.site_id returning s.id)
  select count(*) into v_count from upd;perform public.lb_recalculate_site_score(id) from public.lb_sites;return v_count;
end;$$;

create or replace function public.lb_recalculate_site_score(p_site_id uuid)
returns numeric language plpgsql security definer set search_path=public as $$
declare s public.lb_sites%rowtype;total numeric:=0;weight numeric:=0;result numeric;begin
  select * into s from public.lb_sites where id=p_site_id;if not found then return null;end if;
  if s.grid_score is not null then total:=total+s.grid_score*25;weight:=weight+25;end if;
  if s.land_score is not null then total:=total+s.land_score*20;weight:=weight+20;end if;
  if s.planning_score is not null then total:=total+s.planning_score*15;weight:=weight+15;end if;
  if s.agricultural_score is not null then total:=total+s.agricultural_score*10;weight:=weight+10;end if;
  if s.topography_score is not null then total:=total+s.topography_score*10;weight:=weight+10;end if;
  if s.solar_score is not null then total:=total+s.solar_score*10;weight:=weight+10;end if;
  if s.ownership_score is not null then total:=total+s.ownership_score*10;weight:=weight+10;end if;
  result:=case when weight=0 then null else round(total/weight,1) end;update public.lb_sites set site_score=result,updated_at=now() where id=p_site_id;return result;
end;$$;

revoke all on public.lb_constraint_features,public.lb_constraint_imports,public.lb_site_constraints from anon,authenticated;
revoke all on function public.lb_ingest_constraint_batch(text,jsonb,integer,boolean,text) from public,anon,authenticated;
revoke all on function public.lb_refresh_constraint_intersections(text,numeric) from public,anon,authenticated;
revoke all on function public.lb_apply_agricultural_classification() from public,anon,authenticated;
revoke all on function public.lb_apply_planning_constraint_scores(text[]) from public,anon,authenticated;
grant execute on function public.lb_ingest_constraint_batch(text,jsonb,integer,boolean,text) to service_role;
grant execute on function public.lb_refresh_constraint_intersections(text,numeric) to service_role;
grant execute on function public.lb_apply_agricultural_classification() to service_role;
grant execute on function public.lb_apply_planning_constraint_scores(text[]) to service_role;
