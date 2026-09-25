
create or replace function public.lb_acq_recompute_value()
returns trigger
language plpgsql
security invoker
set search_path=public
as $$
declare
  v_land_cost numeric;
  v_total_cost numeric;
begin
  v_land_cost := coalesce(new.asking_price_gbp, case when new.currency='GBP' then new.asking_price end, 0);
  if new.estimated_exit_value_gbp is not null and new.estimated_development_cost_gbp is not null then
    v_total_cost := v_land_cost + new.estimated_development_cost_gbp;
    new.estimated_margin_gbp := new.estimated_exit_value_gbp - v_total_cost;
    if coalesce(new.potential_mwp_base,0) > 0 then
      new.estimated_margin_per_mw_gbp := round(new.estimated_margin_gbp / new.potential_mwp_base, 0);
    else
      new.estimated_margin_per_mw_gbp := null;
    end if;
  else
    new.estimated_margin_gbp := null;
    new.estimated_margin_per_mw_gbp := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lb_acq_recompute_value on public.lb_acq_assets;
create trigger trg_lb_acq_recompute_value
before insert or update of asking_price, asking_price_gbp, currency, estimated_development_cost_gbp, estimated_exit_value_gbp, potential_mwp_base
on public.lb_acq_assets
for each row execute function public.lb_acq_recompute_value();

revoke all on function public.lb_acq_recompute_value() from public, anon;
grant execute on function public.lb_acq_recompute_value() to authenticated;
