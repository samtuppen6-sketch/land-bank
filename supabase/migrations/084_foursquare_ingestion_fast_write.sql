create or replace function public.lb_record_foursquare_results(p_results jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  r jsonb;
  c jsonb;
  v_job public.lb_contact_gap_jobs%rowtype;
  v_status text;
  v_type text;
  v_value text;
  v_conf numeric;
  v_saved integer:=0;
  v_jobs integer:=0;
  v_failed integer:=0;
  v_source text;
  v_primary boolean;
  v_website text;
begin
  if jsonb_typeof(p_results)<>'array' then raise exception 'results must be an array'; end if;
  if jsonb_array_length(p_results)>100 then raise exception 'maximum 100 results per batch'; end if;

  for r in select value from jsonb_array_elements(p_results)
  loop
    v_website:=null;

    select * into v_job
    from public.lb_contact_gap_jobs
    where opportunity_id=(r->>'opportunity_id')::uuid
      and provider='foursquare_os'
      and status in ('queued','processing')
    for update;

    if not found then continue; end if;
    v_status:=coalesce(r->>'status','no_contact');
    if v_status not in ('completed','no_contact','failed') then v_status:='failed'; end if;

    if jsonb_typeof(r->'contacts')='array' then
      for c in select value from jsonb_array_elements(r->'contacts')
      loop
        v_type:=lower(coalesce(c->>'type',''));
        v_value:=btrim(coalesce(c->>'value',''));
        if v_type not in ('phone','mobile','email','website') or length(v_value)<4 then continue; end if;
        v_conf:=greatest(0,least(100,coalesce(nullif(c->>'confidence','')::numeric,80)));
        v_source:=left(coalesce(c->>'source_url',r->>'source_url',''),1000);

        select not exists(
          select 1 from public.lb_contact_points x
          where x.organisation_id=v_job.organisation_id
            and x.type=v_type
            and x.is_primary
            and not coalesce(x.do_not_contact,false)
        ) into v_primary;

        if not exists(
          select 1 from public.lb_contact_points x
          where x.organisation_id=v_job.organisation_id
            and x.type=v_type
            and lower(regexp_replace(x.value,'[^a-zA-Z0-9@.+]','','g'))=lower(regexp_replace(v_value,'[^a-zA-Z0-9@.+]','','g'))
        ) then
          insert into public.lb_contact_points(
            organisation_id,type,value,label,is_primary,verification_status,discovery_method,provider,source_url,confidence,found_at,do_not_contact
          ) values (
            v_job.organisation_id,v_type,v_value,'Foursquare OS Places',v_primary,
            case when v_conf>=85 then 'probable' else 'unknown' end,
            'foursquare_os_iceberg_match','foursquare_os',nullif(v_source,''),v_conf,now(),false
          );
          v_saved:=v_saved+1;
        end if;

        if v_type='website' and v_conf>=80 then v_website:=v_value; end if;
      end loop;
    end if;

    if v_website is not null then
      update public.lb_organisations
         set website=coalesce(website,v_website),
             domain=coalesce(domain, regexp_replace(regexp_replace(lower(v_website),'^https?://',''),'[/].*$','')),
             domain_source=coalesce(domain_source,'foursquare_os'),
             domain_confidence=greatest(coalesce(domain_confidence,0),80),
             domain_checked_at=now(), updated_at=now()
       where id=v_job.organisation_id;
    end if;

    update public.lb_contact_gap_jobs
       set status=v_status,
           attempts=attempts+1,
           locked_at=null,
           completed_at=case when v_status in ('completed','no_contact') then now() else completed_at end,
           last_error=case when v_status='failed' then left(coalesce(r->>'error','Foursquare worker failed'),500) else null end,
           last_result=jsonb_build_object(
             'fsq_place_id',r->>'fsq_place_id',
             'match_score',r->'match_score',
             'matched_name',r->>'matched_name',
             'matched_postcode',r->>'matched_postcode',
             'distance_km',r->'distance_km',
             'source_url',r->>'source_url'
           ),
           updated_at=now()
     where id=v_job.id;

    v_jobs:=v_jobs+1;
    if v_status='failed' then v_failed:=v_failed+1; end if;
  end loop;

  -- Heavy portfolio rescoring and queue refreshes run on the existing schedulers.
  -- Keeping this RPC focused on ingestion prevents HTTP transaction timeouts.
  return jsonb_build_object('jobs_recorded',v_jobs,'contacts_saved',v_saved,'failed',v_failed);
end;$$;
revoke all on function public.lb_record_foursquare_results(jsonb) from public;
grant execute on function public.lb_record_foursquare_results(jsonb) to anon,authenticated,service_role;
