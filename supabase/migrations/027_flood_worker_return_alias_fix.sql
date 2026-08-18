create or replace function public.lb_run_flood_batch(p_batch_size integer default 5)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  j record;s record;pt geometry;px numeric;py numeric;resp extensions.http_response;payload jsonb;features jsonb;zone text;sources text;score numeric;url text;attempt_no integer;retry_minutes integer;done_count integer:=0;retry_count integer:=0;fail_count integer:=0;err text;got_lock boolean;
begin
  p_batch_size:=greatest(1,least(10,coalesce(p_batch_size,5)));select pg_try_advisory_xact_lock(hashtext('landbank-v2-flood-worker')) into got_lock;if not got_lock then return jsonb_build_object('status','busy');end if;
  update public.lb_assessment_queue set status='queued',locked_at=null,last_error='Recovered stale worker lock',updated_at=now() where job_type='flood_screen' and status='processing' and locked_at<now()-interval '15 minutes';
  for j in select q.id,q.site_id,q.attempts from public.lb_assessment_queue q where q.job_type='flood_screen' and q.status in('queued','failed') and q.attempts<5 and q.next_attempt_at<=now() order by q.attempts,q.next_attempt_at,q.created_at limit p_batch_size for update skip locked loop
    attempt_no:=coalesce(j.attempts,0)+1;update public.lb_assessment_queue set status='processing',attempts=attempt_no,locked_at=now(),last_error=null,updated_at=now() where id=j.id;
    begin
      select id,name,lat,lng into s from public.lb_sites where id=j.site_id;if s.id is null or s.lat is null or s.lng is null then raise exception 'site has no usable coordinates';end if;
      pt:=ST_Transform(ST_SetSRID(ST_MakePoint(s.lng,s.lat),4326),27700);px:=ST_X(pt);py:=ST_Y(pt);
      url:=format('https://environment.data.gov.uk/geoservices/datasets/04532375-a198-476e-985e-0579a0a11b47/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=dataset-04532375-a198-476e-985e-0579a0a11b47%%3AFlood_Zones_2_3_Rivers_and_Sea&outputFormat=application%%2Fjson&propertyName=flood_zone,flood_source&count=50&CQL_FILTER=INTERSECTS%%28shape%%2CPOINT%%28%s%%20%s%%29%%29',px,py);
      resp:=extensions.http_get(url);if resp.status<>200 then raise exception 'Environment Agency WFS HTTP %',resp.status;end if;payload:=resp.content::jsonb;features:=coalesce(payload->'features','[]'::jsonb);
      select case when bool_or((v->'properties'->>'flood_zone')='FZ3') then 'FZ3' when bool_or((v->'properties'->>'flood_zone')='FZ2') then 'FZ2' else 'FZ1 / no FZ2-3 point intersection' end,string_agg(distinct nullif(v->'properties'->>'flood_source',''),', ') into zone,sources from jsonb_array_elements(features) v;
      if zone is null then zone:='FZ1 / no FZ2-3 point intersection';end if;score:=case when zone='FZ3' then 25 when zone='FZ2' then 60 else 100 end;
      insert into public.lb_site_assessments(site_id,assessment_type,score,status,raw_data,summary,provider,source_ref,assessed_at) values(j.site_id,'environment',score,case when zone='FZ3' then 'flood_zone_3' when zone='FZ2' then 'flood_zone_2' else 'no_fz2_fz3_point_intersection' end,jsonb_build_object('features',features),jsonb_build_object('flood_zone',zone,'flood_source',sources,'screen_type','exact point INTERSECTS','screening_score_only',true),'Environment Agency Flood Map for Planning',url,now()) on conflict(site_id,assessment_type,provider) do update set score=excluded.score,status=excluded.status,raw_data=excluded.raw_data,summary=excluded.summary,source_ref=excluded.source_ref,assessed_at=excluded.assessed_at;
      update public.lb_sites set flood_zone=zone,flood_source=sources,flood_score=score,flood_screened_at=now(),updated_at=now() where id=j.site_id;
      update public.lb_assessment_queue set status='completed',locked_at=null,completed_at=now(),last_error=null,last_result=jsonb_build_object('provider','Environment Agency','flood_zone',zone,'flood_source',sources,'flood_score',score),updated_at=now() where id=j.id;done_count:=done_count+1;
    exception when others then err:=sqlerrm;retry_minutes:=least(120,(5*power(2,greatest(0,attempt_no-1)))::integer);if attempt_no>=5 then update public.lb_assessment_queue set status='failed',locked_at=null,last_error=err,next_attempt_at=now()+make_interval(mins=>retry_minutes),updated_at=now() where id=j.id;fail_count:=fail_count+1;else update public.lb_assessment_queue set status='queued',locked_at=null,last_error=err,next_attempt_at=now()+make_interval(mins=>retry_minutes),updated_at=now() where id=j.id;retry_count:=retry_count+1;end if;end;
  end loop;
  return jsonb_build_object('status','ok','completed',done_count,'requeued',retry_count,'failed',fail_count,'progress',(select to_jsonb(ap) from public.lb_assessment_progress ap where ap.job_type='flood_screen'));
end;$$;
