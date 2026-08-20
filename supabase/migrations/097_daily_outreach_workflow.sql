alter table public.lb_opportunities
  add column if not exists outreach_status text not null default 'not_contacted',
  add column if not exists email_sent_at timestamptz,
  add column if not exists last_called_at timestamptz,
  add column if not exists outreach_selected_on date,
  add column if not exists outreach_updated_at timestamptz not null default now();

alter table public.lb_opportunities
  drop constraint if exists lb_opportunities_outreach_status_check;

alter table public.lb_opportunities
  add constraint lb_opportunities_outreach_status_check
  check (
    outreach_status = any (
      array[
        'not_contacted'::text,
        'email_sent'::text,
        'phoned'::text,
        'email_and_phoned'::text,
        'call_due'::text,
        'callback'::text,
        'interested'::text,
        'not_interested'::text,
        'wrong_information'::text
      ]
    )
  );

create index if not exists lb_opportunities_outreach_status_idx
  on public.lb_opportunities(outreach_status);

create index if not exists lb_opportunities_outreach_selected_on_idx
  on public.lb_opportunities(outreach_selected_on);

create index if not exists lb_opportunities_next_action_at_idx
  on public.lb_opportunities(next_action_at)
  where next_action_at is not null;

comment on column public.lb_opportunities.outreach_status is
  'Sales outreach disposition used by Sales Pro daily queue and Prospects view.';

comment on column public.lb_opportunities.outreach_selected_on is
  'Date this opportunity was admitted to the 15-new-prospects daily queue.';
