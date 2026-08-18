create or replace view public.lb_technical_coverage as
select
  s.id as site_id,
  s.name,
  s.site_score,
  case
    when s.grid_score is not null then s.grid_score
    when s.grid_proximity_score is not null then round(s.grid_proximity_score * .45, 1)
  end as grid_score,
  least(100, round((20 * sqrt(greatest(coalesce(s.parcel_count,0),0)))::numeric,1)) as land_score,
  s.planning_screen_score as planning_score,
  s.agricultural_score,
  s.topography_score,
  s.solar_score,
  s.ownership_score,
  s.flood_score,
  (
    case when (s.grid_score is not null or s.grid_proximity_score is not null) then 30 else 0 end +
    20 +
    case when s.planning_screen_score is not null then 15 else 0 end +
    case when s.agricultural_score is not null then 10 else 0 end +
    case when s.topography_score is not null then 10 else 0 end +
    case when s.solar_score is not null then 10 else 0 end +
    case when s.flood_score is not null then 5 else 0 end
  )::numeric as score_evidence_pct,
  array_remove(array[
    case when s.grid_score is null and s.grid_proximity_score is null then 'grid' end,
    case when s.planning_screen_score is null then 'planning' end,
    case when s.agricultural_score is null then 'agricultural_land' end,
    case when s.topography_score is null then 'topography' end,
    case when s.solar_score is null then 'solar_yield' end,
    case when s.ownership_score is null then 'ownership' end,
    case when s.flood_score is null then 'flood' end
  ], null) as missing_layers,
  s.updated_at
from public.lb_sites s;

grant select on public.lb_technical_coverage to anon,authenticated;

create or replace view public.lb_technical_progress_summary as
select
  count(*) as total_sites,
  count(*) filter(where solar_score is not null) as solar_screened,
  count(*) filter(where planning_score is not null) as planning_scored,
  count(*) filter(where agricultural_score is not null) as agricultural_scored,
  count(*) filter(where grid_score is not null) as grid_scored,
  count(*) filter(where topography_score is not null) as topography_scored,
  count(*) filter(where flood_score is not null) as flood_screened,
  count(*) filter(where ownership_score is not null) as ownership_scored,
  round(avg(score_evidence_pct),1) as mean_score_evidence_pct,
  count(*) filter(where score_evidence_pct>=70) as sites_70pct_evidence
from public.lb_technical_coverage;

grant select on public.lb_technical_progress_summary to anon,authenticated;
