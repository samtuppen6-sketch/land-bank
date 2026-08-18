create or replace function public.lb_run_npg_import_page()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare st public.lb_grid_source_imports%rowtype;resp extensions.http_response;payload jsonb;records jsonb;v_total integer;v_offset integer;v_limit integer;v_next integer;v_complete boolean;v_ingested integer;v_match jsonb:=null;url text;
begin
  select * into st from public.lb_grid_source_imports where source_name='npg_generation_headroom_2026';
  if not found then raise exception 'Northern Powergrid import state missing';end if;
  if st.status='completed' then return jsonb_build_object('status','completed','records_imported',st.records_imported,'source_total',st.source_total);end if;
  v_offset:=coalesce(st.next_offset,0);v_limit:=greatest(1,least(50,coalesce(st.page_size,20)));
  update public.lb_grid_source_imports set status='importing',attempts=attempts+1,last_error=null,started_at=coalesce(started_at,now()),updated_at=now() where source_name='npg_generation_headroom_2026';
  url:=format('https://northernpowergrid.opendatasoft.com/api/explore/v2.1/catalog/datasets/npg_ndp_generation_headroom/records?where=scenario_name%%3D%%22DFES%%202026%%20-%%20Holistic%%20Transition%%22&limit=%s&offset=%s',v_limit,v_offset);
  begin
    resp:=extensions.http_get(url);if resp.status<>200 then raise exception 'Northern Powergrid HTTP %',resp.status;end if;
    payload:=resp.content::jsonb;records:=coalesce(payload->'results','[]'::jsonb);v_total:=coalesce((payload->>'total_count')::integer,0);v_next:=v_offset+jsonb_array_length(records);v_complete:=v_next>=v_total or jsonb_array_length(records)<v_limit;
    v_ingested:=public.lb_ingest_npg_grid_batch(records,v_next,v_total,v_complete);if v_complete then v_match:=public.lb_refresh_npg_grid_matches();end if;
    return jsonb_build_object('status',case when v_complete then 'completed_dataset' else 'page_imported' end,'offset',v_offset,'records',jsonb_array_length(records),'next_offset',v_next,'total',v_total,'complete',v_complete,'ingested',v_ingested,'match_result',v_match);
  exception when others then update public.lb_grid_source_imports set status='failed',last_error=sqlerrm,updated_at=now() where source_name='npg_generation_headroom_2026';return jsonb_build_object('status','failed','error',sqlerrm,'offset',v_offset);end;
end;$$;
revoke all on function public.lb_run_npg_import_page() from public,anon,authenticated;
grant execute on function public.lb_run_npg_import_page() to service_role;

do $$ declare v_jobid bigint; begin
  select jobid into v_jobid from cron.job where jobname='landbank-npg-grid-import' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid);end if;
  perform cron.schedule('landbank-npg-grid-import','* * * * *','select public.lb_run_npg_import_page();');
end $$;
