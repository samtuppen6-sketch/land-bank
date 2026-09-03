-- Restore the secured LandBank browser contract after the RLS lockdown.
-- Browser users must authenticate and be explicitly listed here.

create table if not exists private.lb_authorized_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  granted_at timestamptz not null default now(),
  granted_by text not null default 'migration'
);

revoke all on table private.lb_authorized_users from public, anon, authenticated;

insert into private.lb_authorized_users (user_id, active, granted_by)
select id, true, 'restore_authenticated_sales_access'
from auth.users
where email = 'samtuppen6@gmail.com'
on conflict (user_id) do update
set active = excluded.active,
    granted_at = now(),
    granted_by = excluded.granted_by;

create or replace function private.lb_access_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.lb_authorized_users a
    join public.profiles p on p.id = a.user_id
    where a.user_id = (select auth.uid())
      and a.active is true
      and p.active is true
  )
$$;

revoke all on function private.lb_access_allowed() from public, anon;
grant execute on function private.lb_access_allowed() to authenticated, service_role;

-- Security-invoker sales views need SELECT on every underlying relation.
-- RLS remains the row-level gate and calls private.lb_access_allowed().
do $$
declare
  r record;
begin
  for r in
    select c.oid::regclass as relation_name, c.relkind
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'lb\_%' escape '\'
      and c.relkind in ('r', 'p', 'v', 'm')
  loop
    execute format('revoke all on %s from anon', r.relation_name);
    execute format('grant select on %s to authenticated', r.relation_name);
  end loop;
end
$$;

-- Preserve the token-scoped public form. It exposes no direct table access.
grant execute on function public.lb_public_qualification_get(uuid) to anon, authenticated;
grant execute on function public.lb_public_qualification_submit(
  uuid, boolean, boolean, numeric, numeric, boolean, text, text, boolean,
  text, boolean, text, text, boolean, boolean, text, text
) to anon, authenticated;

