-- Customers and their events. A customer row is created automatically when a
-- (non-owner) user signs up.

create table public.customers (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique references auth.users (id) on delete set null,
  full_name     text not null,
  email         text,
  phone         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger customers_updated_at before update on public.customers
  for each row execute function private.set_updated_at();

create table public.events (
  id                 uuid primary key default gen_random_uuid(),
  customer_id        uuid not null references public.customers (id) on delete cascade,
  event_type         text not null,
  event_date         date not null,
  adults             int not null check (adults >= 0),
  children           int not null check (children >= 0),
  vegetarian_guests  int not null default 0 check (vegetarian_guests >= 0),
  vegan_guests       int not null default 0 check (vegan_guests >= 0),
  restricted_guests  int not null default 0 check (restricted_guests >= 0),
  dietary_notes      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (adults + children > 0)
);
create index events_customer_id_idx on public.events (customer_id);
create trigger events_updated_at before update on public.events
  for each row execute function private.set_updated_at();

-- The signed-in user's customer id. Runs as the caller, so customers RLS still applies.
create function private.current_customer_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select c.id from public.customers c where c.auth_user_id = (select auth.uid());
$$;
grant execute on function private.current_customer_id() to authenticated, service_role;

-- New sign-ups get a customer row. full_name from user_metadata is display data only,
-- never used for authorization.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.raw_app_meta_data ->> 'role', '') <> 'owner' then
    insert into public.customers (auth_user_id, full_name, email, phone)
    values (
      new.id,
      coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1)),
      new.email,
      nullif(new.raw_user_meta_data ->> 'phone', '')
    );
  end if;
  return new;
end;
$$;
revoke execute on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();
