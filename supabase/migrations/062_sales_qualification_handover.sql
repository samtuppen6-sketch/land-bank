alter table public.lb_qualifications
  add column if not exists authorised_decision_maker boolean,
  add column if not exists interested_in_solar_income boolean,
  add column if not exists large_vehicle_access boolean,
  add column if not exists site_visit_interest boolean,
  add column if not exists consent_to_share boolean,
  add column if not exists preferred_contact_time text,
  add column if not exists handover_notes text,
  add column if not exists qualified_at timestamptz;

alter table public.lb_opportunities
  add column if not exists handover_status text not null default 'not_ready',
  add column if not exists handover_score numeric,
  add column if not exists handed_over_at timestamptz,
  add column if not exists handover_recipient text,
  add column if not exists handover_reference text;

do $$ begin
  alter table public.lb_opportunities add constraint lb_opportunities_handover_status_check check(handover_status in ('not_ready','ready','handed_over','accepted','rejected'));
exception when duplicate_object then null; end $$;

create or replace function public.lb_refresh_handover_readiness()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
  with c as (
    select o.id,
      least(100,(case when q.interested_in_solar_income is true then 25 else 0 end)+(case when q.authorised_decision_maker is true then 20 else 0 end)+(case when coalesce(q.acres_available,q.usable_acres)>0 then 20 else 0 end)+(case when q.consent_to_share is true then 15 else 0 end)+(case when q.large_vehicle_access is true then 5 else 0 end)+(case when q.contiguous is true then 5 else 0 end)+(case when q.current_land_use is not null and trim(q.current_land_use)<>'' then 5 else 0 end)+(case when q.occupier_or_tenant is not null and trim(q.occupier_or_tenant)<>'' then 5 else 0 end))::numeric score,
      q.interested_in_solar_income,q.authorised_decision_maker,q.consent_to_share,coalesce(q.acres_available,q.usable_acres) acres
    from public.lb_opportunities o left join public.lb_qualifications q on q.opportunity_id=o.id
  ), upd as (
    update public.lb_opportunities o set handover_score=c.score,
      handover_status=case when o.handover_status in ('handed_over','accepted','rejected') then o.handover_status when c.interested_in_solar_income is true and c.authorised_decision_maker is true and c.consent_to_share is true and coalesce(c.acres,0)>0 then 'ready' else 'not_ready' end,updated_at=now()
    from c where o.id=c.id returning o.id
  ) select count(*) into v_count from upd;
  return v_count;
end;$$;

create or replace function public.lb_mark_handed_over(p_opportunity_id uuid,p_recipient text default null,p_reference text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_status text;begin
  perform public.lb_refresh_handover_readiness();
  select handover_status into v_status from public.lb_opportunities where id=p_opportunity_id;
  if v_status is null then raise exception 'Opportunity not found'; end if;
  if v_status<>'ready' then raise exception 'Opportunity is not ready for handover'; end if;
  update public.lb_opportunities set handover_status='handed_over',handed_over_at=now(),handover_recipient=p_recipient,handover_reference=p_reference,stage=case when stage in ('identified','researching','contact_ready','outreach_started','connected') then 'qualified_interest' else stage end,updated_at=now() where id=p_opportunity_id;
  update public.lb_qualifications set qualified_at=coalesce(qualified_at,now()),updated_at=now() where opportunity_id=p_opportunity_id;
  return jsonb_build_object('opportunity_id',p_opportunity_id,'status','handed_over','handed_over_at',now());
end;$$;

grant execute on function public.lb_mark_handed_over(uuid,text,text) to anon,authenticated,service_role;
revoke all on function public.lb_refresh_handover_readiness() from public,anon,authenticated;
grant execute on function public.lb_refresh_handover_readiness() to service_role;
select public.lb_refresh_handover_readiness();
select cron.unschedule(jobid) from cron.job where jobname='landbank-handover-readiness';
select cron.schedule('landbank-handover-readiness','*/5 * * * *','select public.lb_refresh_handover_readiness();');