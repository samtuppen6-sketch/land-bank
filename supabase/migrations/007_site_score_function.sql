create or replace function public.lb_recalculate_site_score(p_site_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.lb_sites%rowtype;
  total numeric := 0;
  weight numeric := 0;
  result numeric;
begin
  select * into s from public.lb_sites where id=p_site_id;
  if not found then return null; end if;

  if s.grid_score is not null then total:=total+s.grid_score*25; weight:=weight+25; end if;
  if s.land_score is not null then total:=total+s.land_score*20; weight:=weight+20; end if;
  if s.planning_score is not null then total:=total+s.planning_score*15; weight:=weight+15; end if;
  if s.solar_score is not null then total:=total+s.solar_score*10; weight:=weight+10; end if;
  if s.ownership_score is not null then total:=total+s.ownership_score*10; weight:=weight+10; end if;

  result := case when weight=0 then null else round(total/weight,1) end;
  update public.lb_sites set site_score=result, updated_at=now() where id=p_site_id;
  return result;
end;
$$;

revoke all on function public.lb_recalculate_site_score(uuid) from public, anon;
grant execute on function public.lb_recalculate_site_score(uuid) to service_role;

do $$
declare r record;
begin
  for r in select id from public.lb_sites where planning_score is not null or solar_score is not null or grid_score is not null or land_score is not null or ownership_score is not null loop
    perform public.lb_recalculate_site_score(r.id);
  end loop;
end $$;
