-- Grants and RLS for leads.
--   anon          can insert a contact-form lead only; cannot read anything
--   customer      can create/update their own open started_order lead only
--   owner         reads, updates and deletes all leads
-- Default privileges already revoke everything on new tables (20261105104534_foundation.sql),
-- so this migration only adds what each role actually needs.

alter table public.leads enable row level security;

grant insert (source, full_name, phone, event_type, event_date, referral_source, note, details)
  on public.leads to anon;

grant select, insert, update, delete on public.leads to authenticated;

-- One merged INSERT policy (not two), same reasoning as
-- 20261105104817_merge_orders_update_policies.sql. Covers both anon and signed-in visitors
-- (a customer or the owner browsing while logged in reuses the same Supabase session, so the
-- contact form must work for them too) submitting a contact-form lead, and a customer creating
-- their own started_order lead.
create policy "Anyone can submit a contact-form lead, customers their own started_order lead" on public.leads
  for insert to anon, authenticated
  with check (
    source = 'contact_form'
    or (source = 'started_order' and customer_id = (select private.current_customer_id()))
  );

-- One merged UPDATE policy (not two), same reasoning as
-- 20261105104817_merge_orders_update_policies.sql: avoids an advisor "multiple permissive
-- policies" finding for the same role/action.
create policy "Customers update their own open lead, owner updates all" on public.leads
  for update to authenticated
  using (
    (source = 'started_order' and customer_id = (select private.current_customer_id())
      and status in ('new', 'contacted'))
    or (select private.is_owner())
  )
  with check (
    customer_id = (select private.current_customer_id())
    or (select private.is_owner())
  );

-- PostgREST's UPDATE appends RETURNING, which Postgres filters through the SELECT policy too,
-- not only the UPDATE policy's USING clause (see the supabase skill's "UPDATE requires a SELECT
-- policy" note) — without this, the upsert in /order/ would silently affect 0 rows for a customer.
create policy "Customers read their own started_order lead, owner reads all" on public.leads
  for select to authenticated
  using (
    (source = 'started_order' and customer_id = (select private.current_customer_id()))
    or (select private.is_owner())
  );

create policy "Owner deletes leads" on public.leads
  for delete to authenticated
  using ((select private.is_owner()));
