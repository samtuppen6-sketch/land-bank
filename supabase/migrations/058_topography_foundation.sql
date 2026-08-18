alter table public.lb_sites
  add column if not exists topography_median_slope_deg numeric,
  add column if not exists topography_p90_slope_deg numeric,
  add column if not exists topography_relief_m numeric,
  add column if not exists topography_score_confidence numeric,
  add column if not exists topography_screened_at timestamptz,
  add column if not exists topography_evidence_class text;

insert into public.lb_assessment_queue(site_id,job_type,status,attempts,next_attempt_at)
select id,'topography','queued',0,now()
from public.lb_sites
where lat is not null and lng is not null and osgb_easting is not null and osgb_northing is not null
on conflict(site_id,job_type) do nothing;

create or replace function public.lb_kick_topography_batch(p_batch_size integer default 4)
returns bigint language plpgsql security definer set search_path=public,net,vault as $$
declare v_key text;v_request_id bigint;begin
 select decrypted_secret into v_key from vault.decrypted_secrets where name='landbank_batch_key' limit 1;
 if v_key is null then raise exception 'landbank_batch_key missing';end if;
 select net.http_post(url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/assess-topography-batch',body:=jsonb_build_object('batch_size',greatest(1,least(8,p_batch_size))),headers:=jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),timeout_milliseconds:=120000) into v_request_id;
 return v_request_id;end;$$;
revoke all on function public.lb_kick_topography_batch(integer) from public,anon,authenticated;
grant execute on function public.lb_kick_topography_batch(integer) to service_role;
select cron.unschedule(jobid) from cron.job where jobname='landbank-topography-screen';
select cron.schedule('landbank-topography-screen','* * * * *','select public.lb_kick_topography_batch(8);');