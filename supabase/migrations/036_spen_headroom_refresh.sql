create or replace function public.lb_refresh_spen_spm_headroom()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare resp extensions.http_response;body jsonb;records jsonb;v_count integer;v_ingested integer;v_url text:='https://xdoqclrwdduncjaxtixp.supabase.co/functions/v1/extract-spen-spm-workbook';
begin
  resp:=extensions.http_post(v_url,'{}'::text,'application/json');
  if resp.status<>200 then raise exception 'SPEN extractor HTTP %: %',resp.status,left(resp.content,500);end if;
  body:=resp.content::jsonb;if body?'error' then raise exception 'SPEN extractor error: %',body->>'error';end if;
  records:=coalesce(body->'records','[]'::jsonb);if jsonb_typeof(records)<>'array' then raise exception 'SPEN extractor returned invalid records payload';end if;
  v_count:=jsonb_array_length(records);if v_count=0 then raise exception 'SPEN extractor returned zero rows';end if;
  v_ingested:=public.lb_ingest_spen_spm_headroom(records,v_count);
  return jsonb_build_object('status','completed','source_rows',v_count,'ingested_rows',v_ingested,'workbook_modified',body->>'workbook_modified','scenario',body->>'scenario','generation_type',body->>'generation_type','year',body->>'year');
end;$$;
revoke all on function public.lb_refresh_spen_spm_headroom() from public,anon,authenticated;
grant execute on function public.lb_refresh_spen_spm_headroom() to service_role;
drop function if exists public.lb_kick_spen_spm_headroom_import();
