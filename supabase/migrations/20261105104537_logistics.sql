-- Logistics: delivery zones, pickup/delivery time slots, and dates closed for orders.

create table public.delivery_zones (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  fee         numeric(10,2) not null check (fee >= 0),
  definition  jsonb not null,            -- shape depends on OPEN_DECISIONS #19
  is_active   boolean not null default true
);

create table public.time_slots (
  id                uuid primary key default gen_random_uuid(),
  fulfillment_type  public.fulfillment_type not null,
  weekday           smallint check (weekday between 0 and 6),   -- null = every day
  start_time        time not null,
  end_time          time not null,
  capacity          int check (capacity > 0),
  is_active         boolean not null default true,
  check (end_time > start_time)
);

create table public.blocked_dates (
  id      uuid primary key default gen_random_uuid(),
  date    date not null unique,
  reason  text
);
