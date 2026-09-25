
alter table public.lb_acq_assets
  add column if not exists asset_class text
    check (asset_class is null or asset_class in ('raw_land','land_with_rights','project_rights','consented_project','ready_to_build','operational')),
  add column if not exists control_strategy text
    check (control_strategy is null or control_strategy in ('purchase','conditional_purchase','option','exclusivity','joint_venture','rights_acquisition')),
  add column if not exists grid_rights_status text,
  add column if not exists planning_rights_status text,
  add column if not exists target_exit_stage text
    check (target_exit_stage is null or target_exit_stage in ('land_control','planning','grid_secured','ready_to_build','construction','operational')),
  add column if not exists monetisation_route text
    check (monetisation_route is null or monetisation_route in ('sell_project_rights','sell_rtb','joint_venture','build_and_hold','build_and_sell')),
  add column if not exists estimated_development_cost_gbp numeric
    check (estimated_development_cost_gbp is null or estimated_development_cost_gbp >= 0),
  add column if not exists estimated_exit_value_gbp numeric
    check (estimated_exit_value_gbp is null or estimated_exit_value_gbp >= 0),
  add column if not exists estimated_margin_gbp numeric,
  add column if not exists estimated_margin_per_mw_gbp numeric;

update public.lb_acq_assets set asset_class='raw_land' where asset_class is null;

create table if not exists public.lb_acq_targets (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  monthly_realised_margin_target_gbp numeric not null check (monthly_realised_margin_target_gbp > 0),
  annual_realised_margin_target_gbp numeric not null check (annual_realised_margin_target_gbp > 0),
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.lb_acq_targets enable row level security;
drop policy if exists authenticated_acq_targets_access on public.lb_acq_targets;
create policy authenticated_acq_targets_access on public.lb_acq_targets
for all to authenticated
using ((select private.lb_access_allowed()))
with check ((select private.lb_access_allowed()));

revoke all on public.lb_acq_targets from anon;
grant select, insert, update on public.lb_acq_targets to authenticated;

insert into public.lb_acq_targets(name, monthly_realised_margin_target_gbp, annual_realised_margin_target_gbp, notes)
values (
  'LandBank B core target',
  1000000,
  12000000,
  'Internal operating target. Realised project margin/value is not guaranteed; use evidence-backed deal economics only.'
)
on conflict (name) do update
set monthly_realised_margin_target_gbp=excluded.monthly_realised_margin_target_gbp,
    annual_realised_margin_target_gbp=excluded.annual_realised_margin_target_gbp,
    notes=excluded.notes,
    active=true,
    updated_at=now();

create or replace view public.lb_acq_value_dashboard
with (security_invoker=true)
as
with t as (
  select *
  from public.lb_acq_targets
  where active=true
  order by updated_at desc
  limit 1
)
select
  t.monthly_realised_margin_target_gbp,
  t.annual_realised_margin_target_gbp,
  coalesce(sum(a.estimated_margin_gbp) filter (
    where a.stage not in ('rejected') and a.screening_status <> 'reject'
  ),0)::numeric as estimated_live_pipeline_margin_gbp,
  coalesce(sum(a.potential_mwp_base) filter (
    where a.stage not in ('rejected') and a.screening_status <> 'reject'
  ),0)::numeric as potential_live_pipeline_mw,
  count(*) filter (where a.asset_class='ready_to_build')::bigint as rtb_assets,
  count(*) filter (where a.asset_class in ('project_rights','consented_project'))::bigint as development_rights_assets,
  count(*) filter (where a.asset_class in ('raw_land','land_with_rights') or a.asset_class is null)::bigint as land_assets,
  case when t.annual_realised_margin_target_gbp > 0
       then round(
         coalesce(sum(a.estimated_margin_gbp) filter (
           where a.stage not in ('rejected') and a.screening_status <> 'reject'
         ),0) / t.annual_realised_margin_target_gbp * 100,1
       )
  end as target_coverage_pct
from t
left join public.lb_acq_assets a on true
group by t.monthly_realised_margin_target_gbp,t.annual_realised_margin_target_gbp;

grant select on public.lb_acq_value_dashboard to authenticated;
revoke all on public.lb_acq_value_dashboard from anon;
