create or replace view public.lb_sales_todo
with (security_invoker = true)
as
with todo_items as (
  select
    'task'::text as source_type,
    t.id::text as source_id,
    t.opportunity_id,
    t.site_id,
    t.type as todo_type,
    t.title as action_title,
    t.notes,
    t.due_at,
    t.priority,
    t.created_at
  from public.lb_tasks t
  where t.due_at is not null
    and t.completed_at is null

  union all

  select
    'next_action'::text as source_type,
    o.id::text as source_id,
    o.id as opportunity_id,
    o.site_id,
    'next_action'::text as todo_type,
    coalesce(nullif(btrim(o.next_action), ''), 'Follow up') as action_title,
    null::text as notes,
    o.next_action_at as due_at,
    'normal'::text as priority,
    o.updated_at as created_at
  from public.lb_opportunities o
  where o.next_action_at is not null
    and nullif(btrim(o.next_action), '') is not null
)
select
  i.source_type,
  i.source_id,
  i.opportunity_id,
  i.site_id,
  i.todo_type,
  i.action_title,
  i.notes,
  i.due_at,
  i.priority,
  i.created_at,
  w.site_name,
  w.organisation_name,
  w.county,
  w.postcode,
  w.decision_makers,
  w.phone,
  w.phone_trust_label,
  w.phone_trust_reason,
  w.call_priority_score,
  w.site_potential_score,
  w.stage
from todo_items i
left join public.lb_sales_workspace w
  on w.opportunity_id = i.opportunity_id;

grant select on public.lb_sales_todo to anon, authenticated;