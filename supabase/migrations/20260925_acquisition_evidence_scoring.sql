-- Evidence-aware acquisition scoring for LandBank purchase opportunities.
-- Missing components are excluded from the denominator rather than scored as zero.

create or replace function public.lb_refresh_acquisition_scores(p_asset_id uuid default null)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_rows integer := 0;
begin
  with base as (
    select
      a.id,
      coalesce(a.acreage_usable, a.acreage_total) as model_acres,
      coalesce(a.asking_price_gbp, case when a.currency='GBP' then a.asking_price end) as model_price_gbp,
      (
        case when a.grid_score is not null then 30 else 0 end +
        case when a.land_score is not null then 15 else 0 end +
        case when a.planning_score is not null then 15 else 0 end +
        case when a.terrain_score is not null then 10 else 0 end +
        case when a.environmental_score is not null then 10 else 0 end +
        case when a.economics_score is not null then 15 else 0 end +
        case when a.contactability_score is not null then 5 else 0 end
      )::numeric as available_weight,
      (
        coalesce(a.grid_score * 30,0) +
        coalesce(a.land_score * 15,0) +
        coalesce(a.planning_score * 15,0) +
        coalesce(a.terrain_score * 10,0) +
        coalesce(a.environmental_score * 10,0) +
        coalesce(a.economics_score * 15,0) +
        coalesce(a.contactability_score * 5,0)
      )::numeric as weighted_sum
    from public.lb_acq_assets a
    where p_asset_id is null or a.id = p_asset_id
  ),
  calc as (
    select
      b.*,
      case when b.available_weight > 0
        then round(b.weighted_sum / b.available_weight,1)
      end as calc_score,
      case when b.model_acres > 0 then round((b.model_acres/5.6)::numeric,1) end as mw_low,
      case when b.model_acres > 0 then round((b.model_acres/4.8)::numeric,1) end as mw_base,
      case when b.model_acres > 0 then round((b.model_acres/4.0)::numeric,1) end as mw_high
    from base b
  )
  update public.lb_acq_assets a
  set
    acquisition_score = c.calc_score,
    score_confidence = c.available_weight,
    priority_band = case
      when c.calc_score is null then null
      when c.calc_score >= 80 then 'A'
      when c.calc_score >= 70 then 'B'
      when c.calc_score >= 60 then 'C'
      else 'D'
    end,
    potential_mwp_low = c.mw_low,
    potential_mwp_base = c.mw_base,
    potential_mwp_high = c.mw_high,
    land_cost_per_mwp = case
      when c.model_price_gbp is not null and c.mw_base > 0
      then round((c.model_price_gbp / c.mw_base)::numeric,0)
    end,
    updated_at = now()
  from calc c
  where a.id = c.id;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

revoke all on function public.lb_refresh_acquisition_scores(uuid) from public, anon;
grant execute on function public.lb_refresh_acquisition_scores(uuid) to authenticated;

select public.lb_refresh_acquisition_scores(null);
