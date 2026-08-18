create or replace function public.lb_kick_planning_point_batch(p_batch_size integer default 40)
returns bigint language plpgsql security definer set search_path=public,net,vault as $$
declare v_key text;v_request_id bigint;begin
 select decrypted_secret into v_key from vault.decrypted_secrets where name='landbank_batch_key' limit 1;
 if v_key is null then raise exception 'landbank_batch_key missing';end if;
 select net.http_post(
   url:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/assess-planning-batch',
   body:=jsonb_build_object('batch_size',greatest(1,least(50,p_batch_size))),
   headers:=jsonb_build_object('Content-Type','application/json','x-landbank-batch-key',v_key),
   timeout_milliseconds:=120000
 ) into v_request_id;
 return v_request_id;
end;$$;
revoke all on function public.lb_kick_planning_point_batch(integer) from public,anon,authenticated;
grant execute on function public.lb_kick_planning_point_batch(integer) to service_role;
select cron.unschedule(jobid) from cron.job where jobname='landbank-planning-point-screen';
select cron.schedule('landbank-planning-point-screen','* * * * *','select public.lb_kick_planning_point_batch(40);');