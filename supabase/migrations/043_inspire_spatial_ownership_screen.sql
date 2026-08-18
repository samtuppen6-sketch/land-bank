-- LandBank V2: targeted HMLR INSPIRE spatial ownership screening.
-- The open INSPIRE WMS provides registered freehold index polygon geometry and an INSPIRE/geometry id,
-- but it does not expose the registered title number. A point intersection is therefore supporting evidence only.
-- Ownership is promoted to 100 only when an INSPIRE id is separately resolved to a title number and that title
-- joins to the same corporate proprietor already held in CCOD.

alter table public.lb_ownership_evidence
  drop constraint if exists lb_ownership_evidence_evidence_type_check;

alter table public.lb_ownership_evidence
  add constraint lb_ownership_evidence_evidence_type_check check (
    evidence_type = any(array[
      'title_company_number_exact'::text,
      'title_owner_name_exact'::text,
      'title_relationship_confirmed'::text,
      'registered_address_company_match'::text,
      'probable_operator_match'::text,
      'speculative_match'::text,
      'manual_verified'::text,
      'inspire_spatial_point_match'::text
    ])
  );

create table if not exists public.lb_inspire_screen_queue (
  site_id uuid primary key references public.lb_sites(id) on delete cascade,
  status text not null default 'queued'
    check(status in ('queued','processing','completed','no_hit','failed')),
  attempts integer not null default 0,
  placemarks_returned integer,
  exact_point_hits integer,
  last_error text,
  checked_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists lb_inspire_screen_queue_status_idx
  on public.lb_inspire_screen_queue(status,attempts,updated_at);

create table if not exists public.lb_inspire_title_resolution (
  inspire_id text primary key,
  title_number text not null,
  source text not null,
  source_ref text,
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists lb_inspire_title_resolution_title_idx
  on public.lb_inspire_title_resolution(title_number);

create or replace function public.lb_screen_inspire_site(p_site_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  s public.lb_sites%rowtype;
  v_url text;
  v_kml text;
  v_status integer;
  v_content_type text;
  v_pm text;
  v_inspire_id text;
  v_poly_kml text;
  v_geom geometry;
  v_poly_id uuid;
  v_point geometry;
  v_eps double precision := 0.000011;
  v_placemarks integer := 0;
  v_hits integer := 0;
begin
  select * into s from public.lb_sites where id=p_site_id;
  if not found then
    return jsonb_build_object('site_id',p_site_id,'status','missing_site');
  end if;

  if s.lat is null or s.lng is null then
    update public.lb_inspire_screen_queue
      set status='failed',last_error='Missing coordinates',checked_at=now(),updated_at=now()
      where site_id=p_site_id;
    return jsonb_build_object('site_id',p_site_id,'status','failed','error','Missing coordinates');
  end if;

  v_point := coalesce(s.location_geom,ST_SetSRID(ST_Point(s.lng,s.lat),4326));
  v_url := 'https://inspire.landregistry.gov.uk/inspire/ows?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=inspire%3ACP.CadastralParcel&STYLES=&SRS=EPSG%3A4326&BBOX=' ||
    (s.lng-v_eps)::text || ',' || (s.lat-v_eps)::text || ',' ||
    (s.lng+v_eps)::text || ',' || (s.lat+v_eps)::text ||
    '&WIDTH=64&HEIGHT=64&FORMAT=application%2Fvnd.google-earth.kml%2Bxml&TRANSPARENT=true';

  select h.status,h.content_type,h.content
    into v_status,v_content_type,v_kml
  from extensions.http_get(v_url) h;

  if v_status <> 200 or v_kml is null then
    update public.lb_inspire_screen_queue
      set status='failed',last_error='HMLR WMS HTTP '||coalesce(v_status::text,'null'),checked_at=now(),updated_at=now()
      where site_id=p_site_id;
    return jsonb_build_object('site_id',p_site_id,'status','failed','http_status',v_status);
  end if;

  for v_pm in
    select m[1]
    from regexp_matches(v_kml,'(?s)(<Placemark.*?</Placemark>)','g') m
  loop
    v_placemarks := v_placemarks+1;
    v_inspire_id := nullif((regexp_match(v_pm,'(?s)<name>([^<]+)</name>'))[1],'');
    v_poly_kml := (regexp_match(v_pm,'(?s)(<Polygon>.*?</Polygon>)'))[1];
    if v_inspire_id is null or v_poly_kml is null then continue; end if;

    begin
      v_geom := ST_MakeValid(ST_SetSRID(ST_GeomFromKML(v_poly_kml),4326));
    exception when others then
      continue;
    end;

    if not ST_Intersects(v_geom,v_point) then continue; end if;
    v_hits := v_hits+1;

    insert into public.lb_title_polygons(
      inspire_id,title_number,tenure,geometry,source_date,source,source_ref,raw_data,updated_at
    ) values (
      v_inspire_id,null,'Freehold',v_geom,null,
      'HM Land Registry INSPIRE Index Polygons WMS',
      'https://inspire.landregistry.gov.uk/inspire/ows',
      jsonb_build_object(
        'match_method','exact_site_point_intersection',
        'checked_at',now(),
        'wms_layer','inspire:CP.CadastralParcel',
        'open_dataset_only',true,
        'title_number_exposed',false,
        'warning','INSPIRE geometry is indicative and the current site point may represent a farm address/office rather than the target solar field.'
      ),now()
    )
    on conflict(inspire_id) do update set
      geometry=excluded.geometry,
      tenure=coalesce(public.lb_title_polygons.tenure,excluded.tenure),
      source=excluded.source,
      source_ref=excluded.source_ref,
      raw_data=excluded.raw_data,
      updated_at=now()
    returning id into v_poly_id;

    insert into public.lb_site_title_matches(site_id,title_polygon_id,match_method,confidence,matched_at)
    values(p_site_id,v_poly_id,'site_point_inspire_intersection',70,now())
    on conflict(site_id,title_polygon_id) do update set
      match_method=excluded.match_method,
      confidence=excluded.confidence,
      matched_at=excluded.matched_at;

    insert into public.lb_ownership_evidence(
      site_id,organisation_id,evidence_type,confidence,source,source_ref,details,verified_at
    )
    select p_site_id,o.id,'inspire_spatial_point_match',70,
      'HM Land Registry INSPIRE exact site-point intersection',v_inspire_id,
      jsonb_build_object(
        'inspire_id',v_inspire_id,
        'polygon_area_sqm',round(ST_Area(v_geom::geography)),
        'site_point',ST_AsGeoJSON(v_point)::jsonb,
        'match_method','exact_site_point_intersection',
        'title_number_confirmed',false,
        'note','Spatial supporting evidence only. HMLR open INSPIRE does not expose the registered title number; do not promote to legal owner confirmation without title resolution.'
      ),now()
    from public.lb_organisations o
    where upper(regexp_replace(coalesce(o.company_number,''),'[^A-Z0-9]','','g')) =
          upper(regexp_replace(coalesce(s.legacy_company_number,''),'[^A-Z0-9]','','g'))
    limit 1
    on conflict(site_id,organisation_id,evidence_type,source,source_ref) do update set
      confidence=excluded.confidence,
      details=excluded.details,
      verified_at=excluded.verified_at;
  end loop;

  update public.lb_inspire_screen_queue
    set status=case when v_hits>0 then 'completed' else 'no_hit' end,
        placemarks_returned=v_placemarks,
        exact_point_hits=v_hits,
        last_error=null,
        checked_at=now(),
        updated_at=now()
    where site_id=p_site_id;

  perform public.lb_recalculate_ownership_score(p_site_id);

  return jsonb_build_object(
    'site_id',p_site_id,
    'status',case when v_hits>0 then 'completed' else 'no_hit' end,
    'placemarks',v_placemarks,
    'exact_point_hits',v_hits
  );
exception when others then
  update public.lb_inspire_screen_queue
    set status='failed',last_error=left(sqlerrm,1000),checked_at=now(),updated_at=now()
    where site_id=p_site_id;
  return jsonb_build_object('site_id',p_site_id,'status','failed','error',sqlerrm);
end;
$$;

create or replace function public.lb_run_inspire_spatial_batch(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  v_done integer:=0;
  v_failed integer:=0;
  v_result jsonb;
begin
  for r in
    select q.site_id
    from public.lb_inspire_screen_queue q
    join public.lb_sites s on s.id=q.site_id
    where q.status in ('queued','failed')
      and q.attempts<3
      and coalesce(s.ownership_score,0)>=85
      and coalesce(s.ownership_score,0)<100
    order by q.attempts,q.updated_at,q.site_id
    limit greatest(1,least(coalesce(p_limit,5),20))
    for update of q skip locked
  loop
    update public.lb_inspire_screen_queue
      set status='processing',attempts=attempts+1,updated_at=now()
      where site_id=r.site_id;
    v_result := public.lb_screen_inspire_site(r.site_id);
    if v_result->>'status'='failed' then
      v_failed:=v_failed+1;
    else
      v_done:=v_done+1;
    end if;
  end loop;
  return jsonb_build_object('processed',v_done+v_failed,'successful',v_done,'failed',v_failed);
end;
$$;

create or replace function public.lb_apply_inspire_title_resolutions()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_exact integer:=0;
  v_sites integer:=0;
begin
  update public.lb_title_polygons t
    set title_number=r.title_number,updated_at=now()
  from public.lb_inspire_title_resolution r
  where r.inspire_id=t.inspire_id
    and t.title_number is distinct from r.title_number;

  insert into public.lb_ownership_evidence(
    site_id,organisation_id,evidence_type,confidence,source,source_ref,details,verified_at
  )
  select distinct s.id,o.id,'title_company_number_exact',100,
    'HMLR CCOD title + HMLR INSPIRE spatial polygon exact match',r.title_number,
    jsonb_build_object(
      'title_number',r.title_number,
      'inspire_id',t.inspire_id,
      'company_number',co.company_number,
      'proprietor_name',co.proprietor_name,
      'match_method','resolved_inspire_id_to_title_then_site_point_intersection',
      'title_resolution_source',r.source,
      'spatial_overlap_confirmed',true,
      'warning','Index polygon boundaries are indicative; title plan/register remain authoritative.'
    ),now()
  from public.lb_site_title_matches stm
  join public.lb_title_polygons t on t.id=stm.title_polygon_id
  join public.lb_inspire_title_resolution r on r.inspire_id=t.inspire_id
  join public.lb_corporate_title_owners co on co.title_number=r.title_number
  join public.lb_sites s on s.id=stm.site_id
  join public.lb_organisations o
    on upper(regexp_replace(coalesce(o.company_number,''),'[^A-Z0-9]','','g')) =
       upper(regexp_replace(coalesce(co.company_number,''),'[^A-Z0-9]','','g'))
   and upper(regexp_replace(coalesce(s.legacy_company_number,''),'[^A-Z0-9]','','g')) =
       upper(regexp_replace(coalesce(co.company_number,''),'[^A-Z0-9]','','g'))
  where stm.match_method='site_point_inspire_intersection'
  on conflict(site_id,organisation_id,evidence_type,source,source_ref) do update set
    confidence=excluded.confidence,
    details=excluded.details,
    verified_at=excluded.verified_at;
  get diagnostics v_exact=row_count;

  select count(distinct site_id) into v_sites
  from public.lb_ownership_evidence
  where evidence_type='title_company_number_exact' and confidence=100;

  perform public.lb_recalculate_ownership_score(x.site_id)
  from (
    select distinct site_id
    from public.lb_ownership_evidence
    where evidence_type='title_company_number_exact' and confidence=100
  ) x;

  return jsonb_build_object('exact_evidence_rows_written',v_exact,'title_confirmed_sites',v_sites);
end;
$$;

insert into public.lb_inspire_screen_queue(site_id,status,updated_at)
select id,'queued',now()
from public.lb_sites
where coalesce(ownership_score,0)>=85 and coalesce(ownership_score,0)<100
on conflict(site_id) do nothing;

create or replace view public.lb_inspire_spatial_progress as
select
  (select count(*) from public.lb_inspire_screen_queue) target_sites,
  (select count(*) from public.lb_inspire_screen_queue where status='queued') queued,
  (select count(*) from public.lb_inspire_screen_queue where status='processing') processing,
  (select count(*) from public.lb_inspire_screen_queue where status='completed') completed_with_hit,
  (select count(*) from public.lb_inspire_screen_queue where status='no_hit') completed_no_hit,
  (select count(*) from public.lb_inspire_screen_queue where status='failed') failed,
  (select count(*) from public.lb_site_title_matches where match_method='site_point_inspire_intersection') spatial_matches,
  (select count(distinct inspire_id) from public.lb_title_polygons where source='HM Land Registry INSPIRE Index Polygons WMS') inspire_polygons,
  (select count(*) from public.lb_inspire_title_resolution) resolved_inspire_ids,
  (select count(distinct site_id) from public.lb_ownership_evidence where evidence_type='title_company_number_exact' and confidence=100) title_confirmed_sites;

grant select on public.lb_inspire_spatial_progress to anon,authenticated;

revoke all on public.lb_inspire_screen_queue,public.lb_inspire_title_resolution from anon,authenticated;
revoke all on function public.lb_screen_inspire_site(uuid) from public,anon,authenticated;
revoke all on function public.lb_run_inspire_spatial_batch(integer) from public,anon,authenticated;
revoke all on function public.lb_apply_inspire_title_resolutions() from public,anon,authenticated;
grant execute on function public.lb_screen_inspire_site(uuid) to service_role;
grant execute on function public.lb_run_inspire_spatial_batch(integer) to service_role;
grant execute on function public.lb_apply_inspire_title_resolutions() to service_role;
