alter table public.lb_opportunities add column if not exists outreach_sequence integer;

with explicit_order(name,seq) as (
  values
    ('BAYBUTT HOLDINGS LIMITED',1),
    ('F B PARRISH AND SON LIMITED',2),
    ('KERLEY & CO LIMITED',3),
    ('G.H. DEAN & CO. LIMITED',4),
    ('DAN MACKELDEN LIMITED',5),
    ('WINSORTAN LIMITED',6),
    ('OFF THE LINE LIMITED',7),
    ('GRAY & SONS (CHELMSFORD) LIMITED',8),
    ('ALLEN G. MEALE & SONS LIMITED',9),
    ('STRUTT AND PARKER (FARMS) LIMITED',10),
    ('HEATHPATCH LIMITED',11),
    ('R.B.R. (CROPS) LIMITED',12),
    ('RYLANDS FARM LIMITED',13),
    ('CHILTON HOME FARMS LTD',14),
    ('D & J COLLIER LIMITED',15)
)
update public.lb_opportunities o
set outreach_sequence=e.seq
from explicit_order e
join public.lb_organisations org on upper(org.name)=e.name
where o.organisation_id=org.id
  and o.outreach_selected_on=date '2026-08-20';

create or replace function public.lb_select_daily_outreach()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
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

  select count(*) into v_existing
  from public.lb_opportunities
  where outreach_selected_on=v_date;

  v_need := greatest(0,15-v_existing);
  if v_need=0 then return 0; end if;

  with ranked as (
    select o.id,
           row_number() over (
             order by
               case when w.phone_trust_label in ('confirmed','trusted') and coalesce(w.phone_quality_score,0)>=80 then 0 else 1 end,
               o.call_priority_score desc nulls last,
               w.site_potential_score desc nulls last,
               o.id
           ) + v_existing as seq
    from public.lb_opportunities o
    join public.lb_sales_workspace w on w.opportunity_id=o.id
    where o.outreach_selected_on is null
      and coalesce(o.outreach_status,'not_contacted')='not_contacted'
      and coalesce(o.stage,'') not in ('closed_lost','contracted','construction','commissioned','live')
      and w.email is not null
      and w.email_trust_label in ('confirmed','trusted')
      and coalesce(w.email_quality_score,0)>=80
      and w.email_status in ('verified','probable')
    order by seq
    limit v_need
  )
  update public.lb_opportunities o
     set outreach_selected_on=v_date,
         outreach_sequence=r.seq,
         outreach_updated_at=now(),
         updated_at=now()
    from ranked r
   where o.id=r.id;

  get diagnostics v_added = row_count;
  return v_added;
end;
$function$;

create index if not exists idx_lb_opportunities_outreach_day_sequence
on public.lb_opportunities(outreach_selected_on,outreach_sequence);