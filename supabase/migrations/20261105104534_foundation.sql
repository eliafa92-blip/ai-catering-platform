-- Foundation: enum types, a private schema for helper functions, the updated_at trigger,
-- and least-privilege defaults for the Data API roles.

-- New tables in public grant nothing to anon/authenticated by default.
-- Every table grants exactly what it needs in 20261105104544_rls_policies.sql.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, public;

create type public.pricing_unit     as enum ('per_guest', 'per_tray', 'per_weight', 'per_item');
create type public.kashrut_class    as enum ('meat', 'dairy', 'pareve');
create type public.fulfillment_type as enum ('pickup', 'delivery');
create type public.order_status     as enum ('draft', 'pending_approval', 'approved', 'rejected');
create type public.proposal_status  as enum ('pending', 'approved', 'rejected', 'expired', 'failed');
create type public.allergen_status  as enum ('contains', 'free', 'unknown');

-- Helper functions live here. This schema is not exposed through the Data API.
create schema if not exists private;
grant usage on schema private to anon, authenticated, service_role;

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- The business owner is marked in app_metadata (not user_metadata, which users can edit).
create function private.is_owner()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'owner', false);
$$;

grant execute on function private.is_owner() to anon, authenticated, service_role;
