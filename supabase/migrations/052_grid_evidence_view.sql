drop view if exists public.lb_grid_evidence;
create view public.lb_grid_evidence as
select s.id site_id,s.name site_name,s.dno_licence_operator,s.dno_licence_area,s.grid_score,s.grid_proximity_score,s.grid_score_confidence,s.grid_distance_km,
       g.id grid_node_id,g.name grid_node_name,g.dno grid_node_source,g.voltage_kv,g.generation_headroom_mw,g.data_date,g.source_url,
       case
         when s.grid_score is not null and g.dno='UK Power Networks' then 'published_generation_available_capacity'
         when s.grid_score is not null and g.dno='Northern Powergrid' then 'published_generation_headroom'
         when s.grid_score is not null and g.dno='SSEN' then 'published_generation_headroom'
         when s.grid_score is not null and g.dno='SP Energy Networks' then 'published_generation_headroom'
         when s.grid_score is not null and g.dno='Electricity North West' then 'published_generation_headroom_forecast'
         when s.grid_score is not null then 'published_or_modelled_grid_score'
         when s.grid_proximity_score is not null and g.dno='NGED open-network proxy' then 'high_voltage_proximity_proxy'
         else 'unknown' end evidence_class,
       case when s.grid_score is not null then s.grid_score else round(coalesce(s.grid_proximity_score,0)*0.45,1) end call_signal_score,
       case when s.grid_score is not null then 'Use for origination ranking; still subject to formal connection study.'
            when s.grid_proximity_score is not null then 'Proximity only: useful for call prioritisation, not evidence of available headroom.'
            else 'No meaningful grid evidence yet.' end evidence_note,
       g.raw_data
from public.lb_sites s left join public.lb_grid_nodes g on g.id=s.nearest_grid_node_id;
grant select on public.lb_grid_evidence to anon,authenticated;