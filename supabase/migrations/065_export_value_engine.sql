create table if not exists public.lb_export_model_assumptions (
 id integer primary key default 1 check(id=1),acres_per_mw_conservative numeric not null default 4,acres_per_mw_base numeric not null default 3,acres_per_mw_high_density numeric not null default 2,export_price_low_gbp_mwh numeric not null default 50,export_price_base_gbp_mwh numeric not null default 70,export_price_high_gbp_mwh numeric not null default 90,participation_pool_pct numeric not null default 10,personal_share_of_pool_pct numeric not null default 20,project_years integer not null default 25,updated_at timestamptz not null default now(),notes text not null default 'Origination illustration only. Export price is not a PPA/CfD offer. Capacity depends on field layout, setbacks, grid, planning and design. Participation calculations are subject to contract definitions.'
);
insert into public.lb_export_model_assumptions(id) values(1) on conflict(id) do nothing;
grant select on public.lb_export_model_assumptions to anon,authenticated;
revoke insert,update,delete,truncate,references,trigger on public.lb_export_model_assumptions from anon,authenticated;

create or replace view public.lb_export_value_scenarios as
with y as (select a.site_id,max((a.summary->>'annual_kwh_per_kwp')::numeric) annual_kwh_per_kwp from public.lb_site_assessments a where a.assessment_type='solar' and a.provider='PVGIS 5.3' and a.summary->>'annual_kwh_per_kwp' is not null group by a.site_id),
b as (select o.id opportunity_id,o.site_id,q.acres_available,q.usable_acres,coalesce(q.usable_acres,q.acres_available) model_acres,y.annual_kwh_per_kwp,m.* from public.lb_opportunities o left join public.lb_qualifications q on q.opportunity_id=o.id left join y on y.site_id=o.site_id cross join public.lb_export_model_assumptions m where m.id=1)
select opportunity_id,site_id,model_acres,annual_kwh_per_kwp,
 round(model_acres/acres_per_mw_conservative,2) capacity_mwp_conservative,round(model_acres/acres_per_mw_base,2) capacity_mwp_base,round(model_acres/acres_per_mw_high_density,2) capacity_mwp_high_density,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp,0) annual_generation_mwh_base,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_low_gbp_mwh,0) annual_gross_value_low,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_base_gbp_mwh,0) annual_gross_value_base,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_high_gbp_mwh,0) annual_gross_value_high,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_base_gbp_mwh*project_years,0) gross_25y_constant_price_base,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_base_gbp_mwh*(participation_pool_pct/100),0) indicative_annual_participation_pool,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_base_gbp_mwh*(participation_pool_pct/100)*(personal_share_of_pool_pct/100),0) indicative_annual_personal_share,
 round((model_acres/acres_per_mw_base)*annual_kwh_per_kwp*export_price_base_gbp_mwh*project_years*(participation_pool_pct/100)*(personal_share_of_pool_pct/100),0) indicative_personal_25y_constant_price,
 export_price_low_gbp_mwh,export_price_base_gbp_mwh,export_price_high_gbp_mwh,participation_pool_pct,personal_share_of_pool_pct,project_years,notes
from b where model_acres>0 and annual_kwh_per_kwp>0;
grant select on public.lb_export_value_scenarios to anon,authenticated;

create or replace function public.lb_refresh_export_values()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;begin
 update public.lb_opportunities o set estimated_annual_revenue=v.annual_gross_value_base,estimated_25y_value=v.gross_25y_constant_price_base,estimated_personal_annual_commission=v.indicative_annual_personal_share,estimated_personal_25y_commission=v.indicative_personal_25y_constant_price,probability_weighted_value=round(v.gross_25y_constant_price_base*coalesce(o.probability,0)/100.0,0),updated_at=now() from public.lb_export_value_scenarios v where v.opportunity_id=o.id;
 get diagnostics v_count=row_count;
 update public.lb_sites s set potential_mwp=v.capacity_mwp_base,updated_at=now() from public.lb_export_value_scenarios v where v.site_id=s.id;
 return v_count;end;$$;
revoke all on function public.lb_refresh_export_values() from public,anon,authenticated;grant execute on function public.lb_refresh_export_values() to service_role;
select public.lb_refresh_export_values();
select cron.unschedule(jobid) from cron.job where jobname='landbank-export-value-refresh';
select cron.schedule('landbank-export-value-refresh','*/5 * * * *','select public.lb_refresh_export_values();');