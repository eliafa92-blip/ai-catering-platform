-- Catalog: categories, dishes, dietary data and allergens.
-- Unknown dietary data is NULL (or a missing dish_allergens row), never "no".

create table public.dish_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  int not null default 0,
  is_active   boolean not null default true
);

create table public.dishes (
  id            uuid primary key default gen_random_uuid(),
  category_id   uuid not null references public.dish_categories (id) on delete restrict,
  name          text not null,
  description   text,
  image_path    text,
  pricing_unit  public.pricing_unit not null,
  unit_price    numeric(10,2) not null check (unit_price >= 0),
  unit_label    text,
  currency      char(3) not null default 'ILS',
  min_quantity  numeric(10,2) check (min_quantity > 0),
  is_available  boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index dishes_category_id_idx on public.dishes (category_id);
create trigger dishes_updated_at before update on public.dishes
  for each row execute function private.set_updated_at();

create table public.dish_dietary (
  dish_id        uuid primary key references public.dishes (id) on delete cascade,
  kashrut_class  public.kashrut_class,
  is_vegetarian  boolean,
  is_vegan       boolean,
  verified_at    timestamptz
);

create table public.allergens (
  id    smallint primary key generated always as identity,
  name  text not null unique
);

create table public.dish_allergens (
  dish_id      uuid not null references public.dishes (id) on delete cascade,
  allergen_id  smallint not null references public.allergens (id) on delete cascade,
  status       public.allergen_status not null,
  primary key (dish_id, allergen_id)
);
create index dish_allergens_allergen_id_idx on public.dish_allergens (allergen_id);
