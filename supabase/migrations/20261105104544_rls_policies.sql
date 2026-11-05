-- Grants and Row Level Security.
--
-- Access model:
--   anon (not signed in)     reads the public catalog only
--   customer (signed in)     reads the catalog; reads and edits their own customer row, events,
--                            draft orders and items; reads their own history and AI data
--   owner (app_metadata.role = 'owner')
--                            reads everything; writes the catalog and settings;
--                            approves or rejects submitted orders
--   service_role (backend)   bypasses RLS
--
-- Grants decide which tables and columns a role can touch at all; policies decide which rows.

-- Start from nothing.
revoke all on all tables in schema public from anon, authenticated;
grant all on all tables in schema public to service_role;

-- ---------------------------------------------------------------- catalog & settings
-- Public read, owner write.
do $$
declare
  t text;
begin
  foreach t in array array[
    'dish_categories', 'dishes', 'dish_dietary', 'allergens', 'dish_allergens',
    'delivery_zones', 'time_slots', 'blocked_dates', 'business_settings', 'quantity_rules'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('grant insert, update, delete on public.%I to authenticated', t);

    execute format($p$create policy "Anyone can read %1$s" on public.%1$I
      for select to anon, authenticated using (true)$p$, t);
    execute format($p$create policy "Owner can insert %1$s" on public.%1$I
      for insert to authenticated with check ((select private.is_owner()))$p$, t);
    execute format($p$create policy "Owner can update %1$s" on public.%1$I
      for update to authenticated
      using ((select private.is_owner())) with check ((select private.is_owner()))$p$, t);
    execute format($p$create policy "Owner can delete %1$s" on public.%1$I
      for delete to authenticated using ((select private.is_owner()))$p$, t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------- customers
alter table public.customers enable row level security;
grant select on public.customers to authenticated;
grant update (full_name, email, phone) on public.customers to authenticated;

create policy "Customers read own row, owner reads all" on public.customers
  for select to authenticated
  using (auth_user_id = (select auth.uid()) or (select private.is_owner()));

create policy "Customers update own row" on public.customers
  for update to authenticated
  using (auth_user_id = (select auth.uid()))
  with check (auth_user_id = (select auth.uid()));

-- ---------------------------------------------------------------- events
alter table public.events enable row level security;
grant select, insert, update, delete on public.events to authenticated;

create policy "Customers read own events, owner reads all" on public.events
  for select to authenticated
  using (customer_id = (select private.current_customer_id()) or (select private.is_owner()));

create policy "Customers create own events" on public.events
  for insert to authenticated
  with check (customer_id = (select private.current_customer_id()));

create policy "Customers update own events" on public.events
  for update to authenticated
  using (customer_id = (select private.current_customer_id()))
  with check (customer_id = (select private.current_customer_id()));

create policy "Customers delete own events" on public.events
  for delete to authenticated
  using (customer_id = (select private.current_customer_id()));

-- ---------------------------------------------------------------- orders
alter table public.orders enable row level security;
grant select, delete on public.orders to authenticated;
-- Customers can only set these columns; totals and snapshots are computed in the database.
grant insert (customer_id, event_id, fulfillment_type, requested_at, delivery_address, delivery_zone_id)
  on public.orders to authenticated;
grant update (fulfillment_type, requested_at, delivery_address, delivery_zone_id, status, decision_note)
  on public.orders to authenticated;

create policy "Customers read own orders, owner reads all" on public.orders
  for select to authenticated
  using (customer_id = (select private.current_customer_id()) or (select private.is_owner()));

create policy "Customers create own draft orders" on public.orders
  for insert to authenticated
  with check (
    customer_id = (select private.current_customer_id())
    and status = 'draft'
    and exists (select 1 from public.events e
                where e.id = event_id and e.customer_id = (select private.current_customer_id()))
  );

-- Customers edit drafts and may submit them; the status trigger checks the transition.
create policy "Customers update own draft orders" on public.orders
  for update to authenticated
  using (customer_id = (select private.current_customer_id()) and status = 'draft')
  with check (customer_id = (select private.current_customer_id())
              and status in ('draft', 'pending_approval'));

create policy "Owner decides submitted orders" on public.orders
  for update to authenticated
  using ((select private.is_owner()) and status = 'pending_approval')
  with check ((select private.is_owner()));

create policy "Customers delete own draft orders" on public.orders
  for delete to authenticated
  using (customer_id = (select private.current_customer_id()) and status = 'draft');

-- ---------------------------------------------------------------- order_items
alter table public.order_items enable row level security;
grant select, delete on public.order_items to authenticated;
grant insert (order_id, dish_id, quantity) on public.order_items to authenticated;
grant update (quantity) on public.order_items to authenticated;

create policy "Read items of own orders, owner reads all" on public.order_items
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (select 1 from public.orders o
               where o.id = order_id and o.customer_id = (select private.current_customer_id()))
  );

create policy "Customers add items to own drafts" on public.order_items
  for insert to authenticated
  with check (exists (select 1 from public.orders o
                      where o.id = order_id and o.status = 'draft'
                        and o.customer_id = (select private.current_customer_id())));

create policy "Customers change items in own drafts" on public.order_items
  for update to authenticated
  using (exists (select 1 from public.orders o
                 where o.id = order_id and o.status = 'draft'
                   and o.customer_id = (select private.current_customer_id())))
  with check (exists (select 1 from public.orders o
                      where o.id = order_id and o.status = 'draft'
                        and o.customer_id = (select private.current_customer_id())));

create policy "Customers remove items from own drafts" on public.order_items
  for delete to authenticated
  using (exists (select 1 from public.orders o
                 where o.id = order_id and o.status = 'draft'
                   and o.customer_id = (select private.current_customer_id())));

-- ---------------------------------------------------------------- read-only for clients
-- Written only by triggers or by the backend with the service role.
alter table public.order_status_history enable row level security;
alter table public.ai_conversations enable row level security;
alter table public.ai_change_proposals enable row level security;
alter table public.ai_messages enable row level security;
grant select on public.order_status_history, public.ai_conversations,
                public.ai_change_proposals, public.ai_messages to authenticated;

create policy "Read history of own orders, owner reads all" on public.order_status_history
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (select 1 from public.orders o
               where o.id = order_id and o.customer_id = (select private.current_customer_id()))
  );

create policy "Read conversations of own orders, owner reads all" on public.ai_conversations
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (select 1 from public.orders o
               where o.id = order_id and o.customer_id = (select private.current_customer_id()))
  );

create policy "Read proposals of own orders, owner reads all" on public.ai_change_proposals
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (select 1 from public.orders o
               where o.id = order_id and o.customer_id = (select private.current_customer_id()))
  );

create policy "Read messages of own conversations, owner reads all" on public.ai_messages
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (select 1 from public.ai_conversations c
               join public.orders o on o.id = c.order_id
               where c.id = conversation_id
                 and o.customer_id = (select private.current_customer_id()))
  );
