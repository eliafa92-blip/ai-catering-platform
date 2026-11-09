-- Business settings (exactly one row) and quantity rules.
-- quantity_rules is a first draft: the real formulas wait on OPEN_DECISIONS #3.

create table public.business_settings (
  id                  boolean primary key default true check (id),
  business_name       text,
  currency            char(3) not null default 'ILS',
  vat_rate            numeric(5,4) check (vat_rate between 0 and 1),
  prices_include_vat  boolean,
  min_lead_days       int check (min_lead_days >= 0),
  updated_at          timestamptz not null default now()
);
create trigger business_settings_updated_at before update on public.business_settings
  for each row execute function private.set_updated_at();

create table public.quantity_rules (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid references public.dish_categories (id) on delete cascade,
  dish_id      uuid references public.dishes (id) on delete cascade,
  per_adult    numeric(10,3) not null check (per_adult >= 0),
  per_child    numeric(10,3) not null check (per_child >= 0),
  round_to     numeric(10,2) check (round_to > 0),
  check (num_nonnulls(category_id, dish_id) = 1)
);
create index quantity_rules_category_id_idx on public.quantity_rules (category_id);
create index quantity_rules_dish_id_idx on public.quantity_rules (dish_id);
