create table if not exists public.lb_pipeline_states (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.lb_finalize_planning_scores_if_ready()
returns jsonb language plpgsql security definer set search_path=public as $$
declare required text[]:=array['green-belt','site-of-special-scientific-interest','ancient-woodland','scheduled-monument'];missing text;flood_remaining integer;v_updated integer:=0;
begin
  select string_agg(d,', ') into missing from unnest(required) d where not exists(select 1 from public.lb_constraint_imports i where i.dataset=d and i.status='completed');
  select count(*) into flood_remaining from public.lb_assessment_queue where job_type='flood_screen' and status<>'completed';
  if missing is not null or flood_remaining>0 then return jsonb_build_object('status','waiting','missing_bulk_datasets',missing,'flood_sites_remaining',flood_remaining);end if;
  with penalties as (
    select s.id site_id,coalesce(sum(p.dataset_penalty),0) bulk_penalty,case when s.flood_zone='FZ3' then 25 when s.flood_zone='FZ2' then 15 else 0 end flood_penalty
    from public.lb_sites s left join lateral (select c.dataset,max(c.penalty) dataset_penalty from public.lb_site_constraints c where c.site_id=s.id and c.dataset=any(required) group by c.dataset) p on true group by s.id,s.flood_zone
  ),upd as(update public.lb_sites s set planning_score=greatest(0,100-p.bulk_penalty-p.flood_penalty),updated_at=now() from penalties p where s.id=p.site_id returning s.id)
  select count(*) into v_updated from upd;
  perform public.lb_recalculate_site_score(id) from public.lb_sites;
  insert into public.lb_pipeline_states(key,value,updated_at) values('planning_score_finalized',jsonb_build_object('updated_sites',v_updated,'required_datasets',required,'finalized_at',now()),now()) on conflict(key) do update set value=excluded.value,updated_at=now();
  return jsonb_build_object('status','finalized','updated_sites',v_updated);
end;$$;
revoke all on public.lb_pipeline_states from anon,authenticated;
revoke all on function public.lb_finalize_planning_scores_if_ready() from public,anon,authenticated;
grant execute on function public.lb_finalize_planning_scores_if_ready() to service_role;

do $$ declare v_jobid bigint; begin select jobid into v_jobid from cron.job where jobname='landbank-planning-finalize' limit 1;if v_jobid is not null then perform cron.unschedule(v_jobid);end if;perform cron.schedule('landbank-planning-finalize','*/10 * * * *','select public.lb_finalize_planning_scores_if_ready();');end $$;
