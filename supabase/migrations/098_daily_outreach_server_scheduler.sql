create or replace function public.lb_select_daily_outreach()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamp := timezone('Europe/London', now());
  v_date date := timezone('Europe/London', now())::date;
  v_dow int := extract(isodow from timezone('Europe/London', now()));
  v_hour int := extract(hour from timezone('Europe/London', now()));
  v_existing int;
  v_need int;
  v_added int := 0;
begin
  if v_date < date '2026-08-21' then return 0; end if;
  if v_dow not between 1 and 5 then return 0; end if;
  if v_hour < 7 then return 0; end if;

  select count(*) into v_existing from public.lb_opportunities where outreach_selected_on=v_date;
  v_need := greatest(0,15-v_existing);
  if v_need=0 then return 0; end if;

  with candidates as (
    select o.id
    from public.lb_opportunities o
    join public.lb_sales_workspace w on w.opportunity_id=o.id
    where o.outreach_selected_on is null
      and coalesce(o.outreach_status,'not_contacted')='not_contacted'
      and o.stage not in ('closed_lost','contracted','construction','commissioned','live')
      and w.email is not null
      and w.email_trust_label in ('confirmed','trusted')
      and coalesce(w.email_quality_score,0)>=80
      and w.email_status in ('verified','probable')
    order by
      case when w.phone_trust_label in ('confirmed','trusted') and coalesce(w.phone_quality_score,0)>=80 then 0 else 1 end,
      o.call_priority_score desc nulls last,
      w.site_potential_score desc nulls last,
      o.id
    limit v_need
  )
  update public.lb_opportunities o
     set outreach_selected_on=v_date,
         outreach_updated_at=now(),
         updated_at=now()
    from candidates c
   where o.id=c.id;

  get diagnostics v_added = row_count;
  return v_added;
end;
$$;

create or replace function public.lb_guard_outreach_selection()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_dow int := extract(isodow from timezone('Europe/London', now()));
  v_hour int := extract(hour from timezone('Europe/London', now()));
  v_ok boolean;
begin
  if new.outreach_selected_on is distinct from old.outreach_selected_on and new.outreach_selected_on is not null then
    if timezone('Europe/London', now())::date < date '2026-08-21' or v_dow not between 1 and 5 or v_hour < 7 then
      new.outreach_selected_on := old.outreach_selected_on;
      return new;
    end if;
    select exists(
      select 1 from public.lb_sales_workspace w
      where w.opportunity_id=new.id
        and w.email is not null
        and w.email_trust_label in ('confirmed','trusted')
        and coalesce(w.email_quality_score,0)>=80
        and w.email_status in ('verified','probable')
    ) into v_ok;
    if not v_ok then new.outreach_selected_on := old.outreach_selected_on; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lb_guard_outreach_selection on public.lb_opportunities;
create trigger trg_lb_guard_outreach_selection
before update of outreach_selected_on on public.lb_opportunities
for each row execute function public.lb_guard_outreach_selection();

do $$ begin
  begin perform cron.unschedule('landbank-daily-15-selector'); exception when others then null; end;
  perform cron.schedule('landbank-daily-15-selector','0 * * * *','select public.lb_select_daily_outreach();');
end $$;
