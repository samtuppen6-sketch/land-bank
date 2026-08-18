create table if not exists public.lb_nged_ltds_generation (
 id bigserial primary key, licence text,gsp_group text,bsp text,primary_substation text,connection_voltage_kv numeric,agreed_export_capacity_mw numeric,fuel_type text,connection_status text,source_url text,imported_at timestamptz not null default now()
);
create table if not exists public.lb_nged_ltds_connection_interest (
 id bigserial primary key,licence text,gsp_group text,bsp text,primary_substation text,proposed_voltage_kv numeric,connection_status text,demand_count integer,demand_capacity_mw numeric,generation_count integer,generation_capacity_mw numeric,source_url text,imported_at timestamptz not null default now()
);
create index if not exists lb_nged_ltds_generation_primary_idx on public.lb_nged_ltds_generation(primary_substation);
create index if not exists lb_nged_ltds_interest_primary_idx on public.lb_nged_ltds_connection_interest(primary_substation);
revoke all on public.lb_nged_ltds_generation,public.lb_nged_ltds_connection_interest from anon,authenticated;

create or replace function public.lb_refresh_nged_ltds_evidence()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v5 text;v6 text;v5n integer:=0;v6n integer:=0;
begin
 select content into v5 from extensions.http_get('https://connecteddata.nationalgrid.co.uk/dataset/5c3c9ca0-5c57-4cdc-99be-f31e38d1e825/resource/f9495346-1484-427c-bd06-e6c242839f6e/download/table-5-generation.csv');
 select content into v6 from extensions.http_get('https://connecteddata.nationalgrid.co.uk/dataset/5c3c9ca0-5c57-4cdc-99be-f31e38d1e825/resource/6cfcd593-ea88-4d72-ba8b-bba1ae89b9ff/download/ltds-table-6-interest-in-connections.csv');
 truncate public.lb_nged_ltds_generation,public.lb_nged_ltds_connection_interest;
 insert into public.lb_nged_ltds_generation(licence,gsp_group,bsp,primary_substation,connection_voltage_kv,agreed_export_capacity_mw,fuel_type,connection_status,source_url)
 select a[1],a[2],nullif(a[3],'-'),nullif(a[4],'-'),nullif(a[5],'-')::numeric,nullif(a[6],'-')::numeric,a[7],a[8],'https://connecteddata.nationalgrid.co.uk/dataset/ltds-tabular-model'
 from (select regexp_split_to_array(trim(both E'\r' from line),',') a,row_number() over() rn from regexp_split_to_table(v5,E'\n') line) q where rn>1 and array_length(a,1)>=8 and coalesce(a[1],'')<>'';
 get diagnostics v5n=row_count;
 insert into public.lb_nged_ltds_connection_interest(licence,gsp_group,bsp,primary_substation,proposed_voltage_kv,connection_status,demand_count,demand_capacity_mw,generation_count,generation_capacity_mw,source_url)
 select a[1],a[2],nullif(a[3],'-'),nullif(a[4],'-'),nullif(a[5],'-')::numeric,a[6],nullif(a[7],'')::integer,nullif(a[8],'')::numeric,nullif(a[9],'')::integer,nullif(a[10],'')::numeric,'https://connecteddata.nationalgrid.co.uk/dataset/ltds-tabular-model'
 from (select regexp_split_to_array(trim(both E'\r' from line),',') a,row_number() over() rn from regexp_split_to_table(v6,E'\n') line) q where rn>1 and array_length(a,1)>=10 and coalesce(a[1],'')<>'';
 get diagnostics v6n=row_count;
 return jsonb_build_object('generation_rows',v5n,'connection_interest_rows',v6n);
end;$$;
revoke all on function public.lb_refresh_nged_ltds_evidence() from public,anon,authenticated;
grant execute on function public.lb_refresh_nged_ltds_evidence() to service_role;