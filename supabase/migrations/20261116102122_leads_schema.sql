-- Leads: two sources feed one table.
--   contact_form   an anonymous visitor's "leave your details" submission on the landing page
--   started_order  a signed-in customer who passed event-step validation in /order/ but hasn't
--                   submitted yet; cleared (status -> converted) once they do
-- This is a disposable signal, decoupled from events/orders and their status-transition triggers
-- (ADR-0003) on purpose: a lead is not a draft order and never becomes one automatically.

create type public.lead_source as enum ('contact_form', 'started_order');
create type public.lead_status as enum ('new', 'contacted', 'converted', 'closed');

create table public.leads (
  id              uuid primary key default gen_random_uuid(),
  source          public.lead_source not null,
  status          public.lead_status not null default 'new',
  customer_id     uuid references public.customers (id) on delete set null,
  full_name       text,
  phone           text,
  event_type      text,
  event_date      date,
  referral_source text,
  note            text,
  -- Extra snapshot specific to started_order (e.g. adult/child counts); never a foreign key
  -- into events/orders, so this stays a disposable signal rather than a second order lifecycle.
  details         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint leads_contact_form_has_contact
    check (source <> 'contact_form' or (full_name is not null and phone is not null)),
  constraint leads_started_order_has_customer
    check (source <> 'started_order' or customer_id is not null)
);

-- Re-entering the event step upserts the same open lead instead of creating a duplicate.
create unique index leads_one_open_started_order_per_customer
  on public.leads (customer_id)
  where source = 'started_order' and status in ('new', 'contacted');
create index leads_status_idx on public.leads (status);
create index leads_customer_id_idx on public.leads (customer_id);

create trigger leads_updated_at before update on public.leads
  for each row execute function private.set_updated_at();
