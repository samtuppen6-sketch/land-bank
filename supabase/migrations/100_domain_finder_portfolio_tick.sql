create or replace function public.lb_domain_finder_tick()
returns bigint
language plpgsql
security definer
set search_path='public','cron'
as $$
declare v_jobid bigint;begin
  if not exists(select 1 from public.lb_domain_discovery_queue where domain is null and domain_checked_at is null) then
    select jobid into v_jobid from cron.job where jobname='landbank-domain-finder-enrichment' limit 1;
    if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
    return null;
  end if;
  return public.lb_kick_domain_finder_batch(50,0);
end;$$;
revoke all on function public.lb_domain_finder_tick() from public,anon,authenticated;
grant execute on function public.lb_domain_finder_tick() to service_role;

select cron.schedule('landbank-domain-finder-enrichment','*/3 * * * *','select public.lb_domain_finder_tick();');
