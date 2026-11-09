-- One UPDATE policy on orders instead of two (the advisor flags multiple permissive
-- policies for the same role and action). Same rules as before:
--   customers edit or submit their own drafts; the owner decides submitted orders.
-- The status trigger still checks which transition each of them may make.

drop policy "Customers update own draft orders" on public.orders;
drop policy "Owner decides submitted orders" on public.orders;

create policy "Customers edit own drafts, owner decides submitted orders" on public.orders
  for update to authenticated
  using (
    (customer_id = (select private.current_customer_id()) and status = 'draft')
    or ((select private.is_owner()) and status = 'pending_approval')
  )
  with check (
    (customer_id = (select private.current_customer_id()) and status in ('draft', 'pending_approval'))
    or (select private.is_owner())
  );
