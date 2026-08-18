-- LandBank V2: HMLR CCOD company + property-postcode ownership matching.
-- Point 1 ownership evidence: strong corporate/title relationship (85/100).
-- A later spatial title polygon intersection may promote this to 100/100.

alter table if exists public.lb_corporate_title_owners
  add column if not exists property_address text,
  add column if not exists property_postcode text;

create table if not exists public.lb_ccod_match_filters (
  name text primary key,
  bits bytea not null,
  created_at timestamptz default now()
);

create table if not exists public.lb_ccod_site_pair_candidates (
  id bigserial primary key,
  pair_hash text not null,
  company_number text not null,
  postcode text not null,
  site_id uuid references public.lb_sites(id) on delete cascade,
  organisation_id uuid references public.lb_organisations(id) on delete cascade,
  exact_match boolean not null default false,
  source_ref text not null default 'CCOD_FULL_2026_08',
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  title_number text,
  tenure text,
  property_address text,
  proprietor_name text
);

create index if not exists lb_ccod_site_pair_candidates_company_idx
  on public.lb_ccod_site_pair_candidates(company_number,postcode);

create unique index if not exists lb_ccod_site_pair_candidate_title_uq
  on public.lb_ccod_site_pair_candidates(
    pair_hash,company_number,postcode,coalesce(title_number,''),coalesce(proprietor_name,'')
  );

create or replace function public.lb_refresh_ccod_site_pair_filter()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  v_bits bytea := decode(repeat('00',8192),'hex');
  v_key text;
  v_md5 text;
  h1 bigint;
  h2 bigint;
  pos integer;
  i integer;
  n integer := 0;
  m integer := 8192 * 8;
begin
  for r in
    select upper(regexp_replace(coalesce(legacy_company_number,''),'[^A-Z0-9]','','g')) company_number,
           upper(regexp_replace(coalesce(postcode,''),'[^A-Z0-9]','','g')) postcode
    from public.lb_sites
    where legacy_company_number is not null and postcode is not null
  loop
    v_key := r.company_number || '|' || r.postcode;
    v_md5 := md5(v_key);
    h1 := ('x' || substr(v_md5,1,8))::bit(32)::bigint;
    h2 := ('x' || substr(v_md5,9,8))::bit(32)::bigint;
    if h2 = 0 then h2 := 2654435761; end if;
    for i in 0..6 loop
      pos := ((h1 + i*h2) % m)::integer;
      v_bits := set_bit(v_bits,pos,1);
    end loop;
    n := n + 1;
  end loop;

  insert into public.lb_ccod_match_filters(name,bits,created_at)
  values('SITE_PAIR_V1',v_bits,now())
  on conflict(name) do update set bits=excluded.bits,created_at=excluded.created_at;
  return n;
end;
$$;

create or replace function public.lb_refresh_ccod_site_pair_secondary_filter()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  v_bits bytea := decode(repeat('00',8192),'hex');
  v_key text;
  v_md5 text;
  h1 bigint;
  h2 bigint;
  pos integer;
  i integer;
  n integer := 0;
  m integer := 8192 * 8;
begin
  for r in
    select upper(regexp_replace(coalesce(legacy_company_number,''),'[^A-Z0-9]','','g')) company_number,
           upper(regexp_replace(coalesce(postcode,''),'[^A-Z0-9]','','g')) postcode
    from public.lb_sites
    where legacy_company_number is not null and postcode is not null
  loop
    v_key := 'B|' || r.company_number || '|' || r.postcode;
    v_md5 := md5(v_key);
    h1 := ('x' || substr(v_md5,1,8))::bit(32)::bigint;
    h2 := ('x' || substr(v_md5,9,8))::bit(32)::bigint;
    if h2 = 0 then h2 := 2246822519; end if;
    for i in 0..6 loop
      pos := ((h1 + i*h2) % m)::integer;
      v_bits := set_bit(v_bits,pos,1);
    end loop;
    n := n + 1;
  end loop;

  insert into public.lb_ccod_match_filters(name,bits,created_at)
  values('SITE_PAIR_V2',v_bits,now())
  on conflict(name) do update set bits=excluded.bits,created_at=excluded.created_at;
  return n;
end;
$$;

create or replace function public.lb_stage_ccod_site_pairs(p_payload text)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare v_count integer:=0;
begin
  insert into public.lb_ccod_site_pair_candidates(
    pair_hash,company_number,postcode,title_number,tenure,proprietor_name,property_address,source_ref,created_at
  )
  select split_part(line,E'\t',1),
         split_part(line,E'\t',2),
         split_part(line,E'\t',3),
         nullif(split_part(line,E'\t',4),''),
         nullif(split_part(line,E'\t',5),''),
         nullif(split_part(line,E'\t',6),''),
         nullif(split_part(line,E'\t',7),''),
         'CCOD_FULL_2026_08',now()
  from unnest(string_to_array(p_payload,E'\n')) as line
  where line<>'' and split_part(line,E'\t',1) ~ '^[0-9a-f]{32}$'
  on conflict do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.lb_stage_ccod_site_pairs_compact(p_payload text)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare v_count integer:=0;
begin
  insert into public.lb_ccod_site_pair_candidates(
    pair_hash,company_number,postcode,title_number,tenure,source_ref,created_at
  )
  select md5(
           upper(regexp_replace(split_part(line,E'\t',1),'[^A-Z0-9]','','g')) || '|' ||
           upper(regexp_replace(split_part(line,E'\t',2),'[^A-Z0-9]','','g'))
         ),
         upper(regexp_replace(split_part(line,E'\t',1),'[^A-Z0-9]','','g')),
         upper(regexp_replace(split_part(line,E'\t',2),'[^A-Z0-9]','','g')),
         nullif(split_part(line,E'\t',3),''),
         nullif(split_part(line,E'\t',4),''),
         'CCOD_FULL_2026_08',now()
  from unnest(string_to_array(p_payload,E'\n')) as line
  where line<>'' and split_part(line,E'\t',1)<>'' and split_part(line,E'\t',2)<>''
  on conflict do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.lb_finalize_ccod_site_pair_candidates()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_titles integer:=0;
  v_evidence integer:=0;
  v_parties integer:=0;
  v_sites integer:=0;
begin
  update public.lb_ccod_site_pair_candidates c
  set site_id=s.id,
      organisation_id=o.id,
      exact_match=true,
      verified_at=coalesce(c.verified_at,now())
  from public.lb_sites s
  join public.lb_organisations o
    on upper(regexp_replace(coalesce(o.company_number,''),'[^A-Z0-9]','','g')) =
       upper(regexp_replace(coalesce(s.legacy_company_number,''),'[^A-Z0-9]','','g'))
  where md5(
      upper(regexp_replace(coalesce(s.legacy_company_number,''),'[^A-Z0-9]','','g')) || '|' ||
      upper(regexp_replace(coalesce(s.postcode,''),'[^A-Z0-9]','','g'))
    ) = c.pair_hash;

  update public.lb_ccod_site_pair_candidates
  set exact_match=false
  where verified_at is null;

  with d as (
    select distinct on (c.site_id,c.organisation_id,c.company_number,c.title_number)
      c.site_id,c.organisation_id,c.company_number,c.postcode,c.title_number,c.tenure,
      coalesce(c.proprietor_name,o.name) as proprietor_name,
      c.property_address,c.pair_hash,c.source_ref
    from public.lb_ccod_site_pair_candidates c
    join public.lb_organisations o on o.id=c.organisation_id
    where c.exact_match and c.title_number is not null
    order by c.site_id,c.organisation_id,c.company_number,c.title_number,
             (c.proprietor_name is not null) desc,
             (c.property_address is not null) desc,
             c.id
  )
  insert into public.lb_corporate_title_owners(
    title_number,company_number,proprietor_name,tenure,proprietor_address,
    property_address,property_postcode,source,source_date,raw_data
  )
  select d.title_number,d.company_number,d.proprietor_name,d.tenure,null,
         d.property_address,d.postcode,'HM Land Registry CCOD','2026-08-03'::date,
         jsonb_build_object(
           'match_method','company_number_and_property_postcode_exact',
           'pair_hash',d.pair_hash,
           'source_ref',d.source_ref,
           'proprietor_name_source','ccod_or_company_number_match',
           'spatial_overlap_confirmed',false
         )
  from d
  on conflict(title_number,company_number,proprietor_name) do update
    set tenure=excluded.tenure,
        property_address=excluded.property_address,
        property_postcode=excluded.property_postcode,
        source_date=excluded.source_date,
        raw_data=excluded.raw_data;
  get diagnostics v_titles=row_count;

  with d as (
    select distinct on (c.site_id,c.organisation_id,c.title_number)
      c.site_id,c.organisation_id,c.company_number,c.postcode,c.title_number,c.tenure,
      coalesce(c.proprietor_name,o.name) as proprietor_name,
      c.property_address
    from public.lb_ccod_site_pair_candidates c
    join public.lb_organisations o on o.id=c.organisation_id
    where c.exact_match and c.title_number is not null
    order by c.site_id,c.organisation_id,c.title_number,
             (c.proprietor_name is not null) desc,
             (c.property_address is not null) desc,
             c.id
  )
  insert into public.lb_ownership_evidence(
    site_id,organisation_id,evidence_type,confidence,source,source_ref,details,verified_at
  )
  select d.site_id,d.organisation_id,'title_relationship_confirmed',85,
         'HM Land Registry CCOD company + property postcode exact match',
         d.title_number,
         jsonb_build_object(
           'company_number',d.company_number,
           'property_postcode',d.postcode,
           'property_address',d.property_address,
           'title_number',d.title_number,
           'proprietor_name',d.proprietor_name,
           'tenure',d.tenure,
           'match_method','company_number_and_property_postcode_exact',
           'spatial_overlap_confirmed',false,
           'note','Strong corporate ownership relationship. Title geometry has not yet been intersected with the target land parcel.'
         ),now()
  from d
  on conflict(site_id,organisation_id,evidence_type,source,source_ref) do update
    set confidence=excluded.confidence,
        details=excluded.details,
        verified_at=excluded.verified_at;
  get diagnostics v_evidence=row_count;

  with d as (
    select distinct on (c.site_id,c.organisation_id)
      c.site_id,c.organisation_id,c.company_number,c.postcode
    from public.lb_ccod_site_pair_candidates c
    where c.exact_match
    order by c.site_id,c.organisation_id,c.id
  )
  insert into public.lb_site_parties(
    site_id,organisation_id,relationship,confidence,source,source_ref,verified_at
  )
  select d.site_id,d.organisation_id,'probable_owner',85,
         'HM Land Registry CCOD company + property postcode exact match',
         'ccod-site-pair:'||d.company_number||'|'||d.postcode,now()
  from d
  where not exists (
    select 1 from public.lb_site_parties p
    where p.site_id=d.site_id
      and p.organisation_id=d.organisation_id
      and p.relationship='probable_owner'
      and p.source='HM Land Registry CCOD company + property postcode exact match'
  );
  get diagnostics v_parties=row_count;

  select count(distinct site_id) into v_sites
  from public.lb_ccod_site_pair_candidates
  where exact_match and site_id is not null;

  perform public.lb_recalculate_ownership_score(s.site_id)
  from (
    select distinct site_id
    from public.lb_ccod_site_pair_candidates
    where exact_match and site_id is not null
  ) s;

  return jsonb_build_object(
    'exact_candidate_rows',(select count(*) from public.lb_ccod_site_pair_candidates where exact_match),
    'distinct_site_company_titles',(select count(distinct (site_id,company_number,title_number)) from public.lb_ccod_site_pair_candidates where exact_match),
    'exact_sites',v_sites,
    'title_rows_written',v_titles,
    'ownership_evidence_written',v_evidence,
    'site_parties_written',v_parties,
    'rejected_candidates',(select count(*) from public.lb_ccod_site_pair_candidates where not exact_match)
  );
end;
$$;

revoke all on public.lb_ccod_match_filters,public.lb_ccod_site_pair_candidates from anon,authenticated;
revoke all on function public.lb_refresh_ccod_site_pair_filter() from public,anon,authenticated;
revoke all on function public.lb_refresh_ccod_site_pair_secondary_filter() from public,anon,authenticated;
revoke all on function public.lb_stage_ccod_site_pairs(text) from public,anon,authenticated;
revoke all on function public.lb_stage_ccod_site_pairs_compact(text) from public,anon,authenticated;
revoke all on function public.lb_finalize_ccod_site_pair_candidates() from public,anon,authenticated;
grant execute on function public.lb_refresh_ccod_site_pair_filter() to service_role;
grant execute on function public.lb_refresh_ccod_site_pair_secondary_filter() to service_role;
grant execute on function public.lb_stage_ccod_site_pairs(text) to service_role;
grant execute on function public.lb_stage_ccod_site_pairs_compact(text) to service_role;
grant execute on function public.lb_finalize_ccod_site_pair_candidates() to service_role;
