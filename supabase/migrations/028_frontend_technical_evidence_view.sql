create or replace view public.lb_frontend_workspace_v2 as
select w.*,s.agricultural_grade,s.agricultural_score,s.topography_score,s.flood_zone,s.flood_source,s.flood_score,s.flood_screened_at,s.grid_dno,s.grid_distance_km,s.grid_proximity_score,s.grid_score_confidence,tc.score_evidence_pct,tc.missing_layers
from public.lb_frontend_workspace w
join public.lb_sites s on s.id=w.site_id
join public.lb_technical_coverage tc on tc.site_id=w.site_id;
grant select on public.lb_frontend_workspace_v2 to anon,authenticated;
