-- Orders, their items, and an automatic status history.
-- Status rules are enforced in the database:
--   draft -> pending_approval   by the customer who owns the order (prices are frozen here)
--   pending_approval -> approved | rejected   by the business owner
-- Server-side code (service role, no auth.uid()) may make any transition.

create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  customer_id       uuid not null references public.customers (id) on delete restrict,
  event_id          uuid not null unique references public.events (id) on delete restrict,
  status            public.order_status not null default 'draft',
  version           int not null default 1,
  fulfillment_type  public.fulfillment_type not null,
  requested_at      timestamptz not null,
  delivery_address  text,
  delivery_zone_id  uuid references public.delivery_zones (id) on delete restrict,
  subtotal          numeric(10,2),
  delivery_fee      numeric(10,2),
  total             numeric(10,2),
  submitted_at      timestamptz,
  decided_at        timestamptz,
  decision_note     text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (fulfillment_type = 'pickup' or (delivery_address is not null and delivery_zone_id is not null))
);
create index orders_customer_id_idx on public.orders (customer_id);
create index orders_status_idx on public.orders (status);
create index orders_delivery_zone_id_idx on public.orders (delivery_zone_id);

create table public.order_items (
  id                     uuid primary key default gen_random_uuid(),
  order_id               uuid not null references public.orders (id) on delete cascade,
  dish_id                uuid not null references public.dishes (id) on delete restrict,
  quantity               numeric(10,2) not null check (quantity > 0),
  snapshot_name          text,
  snapshot_pricing_unit  public.pricing_unit,
  snapshot_unit_price    numeric(10,2),
  snapshot_line_total    numeric(10,2),
  unique (order_id, dish_id)
);
create index order_items_dish_id_idx on public.order_items (dish_id);

create table public.order_status_history (
  id           bigint primary key generated always as identity,
  order_id     uuid not null references public.orders (id) on delete cascade,
  from_status  public.order_status,
  to_status    public.order_status not null,
  changed_by   text not null check (changed_by in ('customer', 'owner', 'system')),
  note         text,
  created_at   timestamptz not null default now()
);
create index order_status_history_order_idx on public.order_status_history (order_id, created_at);

-- Validates status transitions, bumps the version, and freezes prices on submission.
-- SECURITY DEFINER so it can write snapshot columns customers cannot write directly.
-- It is a trigger function, so the Data API cannot call it.
create function private.orders_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  trusted boolean := (select auth.uid()) is null;   -- service role or direct DB access
  owner   boolean := private.is_owner();
begin
  new.version    := old.version + 1;
  new.updated_at := now();

  if new.status is distinct from old.status then
    if old.status = 'draft' and new.status = 'pending_approval' then
      if not trusted and owner then
        raise exception 'Only the customer can submit an order' using errcode = '42501';
      end if;
      if not exists (select 1 from public.order_items i where i.order_id = new.id) then
        raise exception 'Cannot submit an order with no items' using errcode = '23514';
      end if;

      update public.order_items i
         set snapshot_name         = d.name,
             snapshot_pricing_unit = d.pricing_unit,
             snapshot_unit_price   = d.unit_price,
             snapshot_line_total   = round(d.unit_price * i.quantity, 2)
        from public.dishes d
       where d.id = i.dish_id and i.order_id = new.id;

      select coalesce(sum(i.snapshot_line_total), 0) into new.subtotal
        from public.order_items i where i.order_id = new.id;
      new.delivery_fee := case
        when new.fulfillment_type = 'delivery'
          then (select z.fee from public.delivery_zones z where z.id = new.delivery_zone_id)
        else 0 end;
      new.total        := new.subtotal + coalesce(new.delivery_fee, 0);
      new.submitted_at := coalesce(new.submitted_at, now());

    elsif old.status = 'pending_approval' and new.status in ('approved', 'rejected') then
      if not trusted and not owner then
        raise exception 'Only the business owner can approve or reject' using errcode = '42501';
      end if;
      new.decided_at := coalesce(new.decided_at, now());

    elsif not trusted then
      raise exception 'Invalid status change: % -> %', old.status, new.status using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;
revoke execute on function private.orders_before_update() from public, anon, authenticated;

create trigger orders_before_update before update on public.orders
  for each row execute function private.orders_before_update();

-- Logs every status a order enters.
create function private.log_order_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (
      new.id,
      case when tg_op = 'UPDATE' then old.status end,
      new.status,
      case when (select auth.uid()) is null then 'system'
           when private.is_owner() then 'owner'
           else 'customer' end
    );
  end if;
  return null;
end;
$$;
revoke execute on function private.log_order_status() from public, anon, authenticated;

create trigger orders_log_status after insert or update of status on public.orders
  for each row execute function private.log_order_status();

-- Changing the dishes in an order counts as a change to the order (used for
-- optimistic locking of AI proposals). Snapshot-only updates do not fire this.
create function private.bump_order_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.orders
     set version = version + 1
   where id = coalesce(new.order_id, old.order_id);
  return null;
end;
$$;
revoke execute on function private.bump_order_version() from public, anon, authenticated;

create trigger order_items_bump_version
  after insert or delete or update of quantity, dish_id on public.order_items
  for each row execute function private.bump_order_version();
