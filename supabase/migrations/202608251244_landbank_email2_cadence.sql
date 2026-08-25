alter table public.lb_opportunities
  add column if not exists email_touch_count smallint not null default 0,
  add column if not exists first_email_sent_at timestamptz,
  add column if not exists second_email_sent_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.lb_opportunities'::regclass
      AND conname = 'lb_opportunities_email_touch_count_check'
  ) THEN
    ALTER TABLE public.lb_opportunities
      ADD CONSTRAINT lb_opportunities_email_touch_count_check
      CHECK (email_touch_count between 0 and 2);
  END IF;
END $$;

create or replace function public.lb_add_working_days(p_from timestamptz, p_days integer)
returns timestamptz
language plpgsql
stable
as $$
declare
  d date := (p_from at time zone 'Europe/London')::date;
  remaining integer := greatest(coalesce(p_days, 0), 0);
begin
  while remaining > 0 loop
    d := d + 1;
    if extract(isodow from d) < 6 then
      remaining := remaining - 1;
    end if;
  end loop;
  return make_timestamptz(
    extract(year from d)::int,
    extract(month from d)::int,
    extract(day from d)::int,
    9, 0, 0,
    'Europe/London'
  );
end;
$$;

update public.lb_opportunities
set email_touch_count = 1,
    first_email_sent_at = coalesce(first_email_sent_at, email_sent_at)
where email_sent_at is not null
  and email_touch_count = 0;

update public.lb_opportunities
set next_action = 'Send Email 2',
    next_action_at = public.lb_add_working_days(coalesce(first_email_sent_at, email_sent_at), 3),
    outreach_updated_at = now()
where outreach_status = 'email_sent'
  and email_touch_count = 1
  and email_sent_at is not null
  and next_action = 'Phone follow-up after email';

create or replace function public.lb_track_email_touch()
returns trigger
language plpgsql
as $$
begin
  if new.email_sent_at is distinct from old.email_sent_at
     and new.email_sent_at is not null then
    if coalesce(old.email_touch_count, 0) = 0 then
      new.email_touch_count := 1;
      new.first_email_sent_at := coalesce(old.first_email_sent_at, new.email_sent_at);
      new.next_action := 'Send Email 2';
      new.next_action_at := public.lb_add_working_days(new.email_sent_at, 3);
    elsif coalesce(old.email_touch_count, 0) = 1 then
      new.email_touch_count := 2;
      new.second_email_sent_at := coalesce(old.second_email_sent_at, new.email_sent_at);
      new.next_action := 'Phone follow-up after Email 2';
      new.next_action_at := public.lb_add_working_days(new.email_sent_at, 3);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lb_track_email_touch on public.lb_opportunities;
create trigger trg_lb_track_email_touch
before update of email_sent_at on public.lb_opportunities
for each row
execute function public.lb_track_email_touch();

create index if not exists idx_lb_opportunities_email_touch_due
  on public.lb_opportunities (email_touch_count, next_action_at)
  where outreach_status = 'email_sent';
