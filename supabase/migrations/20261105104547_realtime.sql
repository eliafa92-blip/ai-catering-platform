-- Realtime: stream row changes for these tables to subscribed clients.
-- Realtime applies each table's RLS, so customers only receive changes to their own rows.
-- (RLS is not applied to DELETE events; those carry only the primary key.)

alter publication supabase_realtime add table
  public.orders,
  public.order_items,
  public.order_status_history,
  public.ai_messages,
  public.ai_change_proposals,
  public.dishes,
  public.blocked_dates;

-- Send the previous row on UPDATE, so clients can see e.g. the old order status.
alter table public.orders replica identity full;
alter table public.order_items replica identity full;
