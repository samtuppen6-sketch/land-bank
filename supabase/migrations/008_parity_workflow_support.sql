create index if not exists lb_tasks_opportunity_created_idx on public.lb_tasks(opportunity_id, created_at desc);
create index if not exists lb_tasks_open_callback_idx on public.lb_tasks(due_at) where type='callback' and completed_at is null;

create or replace view public.lb_dashboard_metrics as
select
  (select count(*) from public.lb_frontend_workspace) as universe,
  (select count(*) from public.lb_frontend_workspace where stage='contact_ready') as contact_ready,
  (select count(*) from public.lb_frontend_workspace where stage not in ('identified','contact_ready','closed_lost')) as active_pipeline,
  (select coalesce(sum(parcel_count),0) from public.lb_frontend_workspace) as land_parcels,
  ((select count(*) from public.lb_frontend_workspace where next_action_at is not null and next_action_at <= now())
   +
   (select count(*) from public.lb_tasks where type='callback' and completed_at is null and due_at is not null and due_at <= now())) as actions_due,
  (select coalesce(sum(probability_weighted_value),0) from public.lb_frontend_workspace) as weighted_pipeline_value,
  (select coalesce(sum(potential_mwp),0) from public.lb_frontend_workspace) as potential_mwp;

grant select on public.lb_dashboard_metrics to anon, authenticated;
