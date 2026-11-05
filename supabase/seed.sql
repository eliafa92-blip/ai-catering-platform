-- Synthetic data for the DEV project only. Every run wipes and rebuilds the data,
-- except demo login users and their customer rows (scripts/seed_dev.py creates those first).
--
-- Part 1: a fixed catalog (dishes, allergens, zones, slots, settings).
-- Part 2: a deterministic generator (setseed) for customers, events, orders, items,
--         status history and AI conversations. Orders go through the real status trigger,
--         so prices are frozen and history is logged exactly as in production.

-- ============================================================ reset
truncate public.ai_messages, public.ai_change_proposals, public.ai_conversations,
         public.order_status_history, public.order_items, public.orders, public.events,
         public.quantity_rules, public.dish_allergens, public.dish_dietary, public.dishes,
         public.dish_categories, public.allergens, public.delivery_zones, public.time_slots,
         public.blocked_dates, public.business_settings
  restart identity cascade;
delete from public.customers where auth_user_id is null;

-- ============================================================ part 1: catalog
insert into public.business_settings (business_name, currency, vat_rate, prices_include_vat, min_lead_days)
values ('קייטרינג דמו', 'ILS', 0.18, true, 3);

insert into public.allergens (name) values
  ('גלוטן'), ('ביצים'), ('חלב'), ('אגוזים'), ('בוטנים'), ('שומשום'), ('סויה'), ('דגים'), ('סלרי'), ('חרדל');

insert into public.dish_categories (name, sort_order) values
  ('סלטים', 1), ('מנות פתיחה', 2), ('עיקריות בשר', 3), ('עיקריות דגים', 4),
  ('תוספות', 5), ('צמחוני וטבעוני', 6), ('קינוחים', 7), ('מאפים', 8);

create temp table _dish (
  name text, cat text, unit public.pricing_unit, price numeric, label text, min_q numeric,
  descr text, kashrut public.kashrut_class, veg boolean, vegan boolean,
  contains text[], free text[], available boolean
) on commit drop;

-- NULL kashrut / veg / vegan = not provided yet (shown as "unknown", never "no").
insert into _dish values
  ('סלט ישראלי',              'סלטים',          'per_tray',   120, 'מגש 30 ס"מ', null, 'עגבניות, מלפפונים ובצל סגול בשמן זית ולימון', 'pareve', true, true, '{}', '{גלוטן,ביצים,חלב}', true),
  ('טאבולה',                  'סלטים',          'per_tray',   135, 'מגש 30 ס"מ', null, 'בורגול, פטרוזיליה, נענע ולימון', 'pareve', true, true, '{גלוטן}', '{}', true),
  ('סלט חצילים במיונז',        'סלטים',          'per_tray',   130, 'מגש 30 ס"מ', null, 'חצילים קלויים על האש', 'pareve', true, false, '{ביצים}', '{}', true),
  ('סלט קינואה וירקות קלויים', 'סלטים',          'per_tray',   160, 'מגש 30 ס"מ', null, 'קינואה, בטטה, פלפלים ועשבי תיבול', 'pareve', true, true, '{}', '{גלוטן}', true),
  ('חומוס ביתי',               'סלטים',          'per_weight',  48, 'ק"ג', 1,    'חומוס עם טחינה גולמית', 'pareve', true, true, '{שומשום}', '{גלוטן}', true),
  ('סלט כרוב סגול ואגוזים',    'סלטים',          'per_tray',   125, 'מגש 30 ס"מ', null, 'כרוב סגול, חמוציות ואגוזי מלך', 'pareve', true, true, '{אגוזים}', '{}', true),
  ('בורקס גבינה',              'מנות פתיחה',     'per_item',     9, 'יחידה', 20,  'בצק עלים במילוי גבינות', 'dairy', true, false, '{גלוטן,חלב,ביצים}', '{}', true),
  ('סיגרים במילוי בשר',        'מנות פתיחה',     'per_item',    11, 'יחידה', 20,  'בצק פילו ובשר בקר מתובל', 'meat', false, false, '{גלוטן}', '{}', true),
  ('מיני פלאפל',               'מנות פתיחה',     'per_item',   4.5, 'יחידה', 50,  'כדורי פלאפל קטנים עם טחינה', 'pareve', true, true, '{שומשום}', '{}', true),
  ('קרפצ''ו סלק',              'מנות פתיחה',     'per_guest',   18, 'לאורח', null, 'סלק אפוי, שמן זית ופרחי מלח', null, true, true, '{}', '{}', true),
  ('שניצל עוף',                'עיקריות בשר',    'per_weight',  95, 'ק"ג', 2,    'חזה עוף בציפוי פירורי לחם', 'meat', false, false, '{גלוטן,ביצים}', '{}', true),
  ('חזה עוף בגריל',            'עיקריות בשר',    'per_weight', 110, 'ק"ג', 2,    'במרינדת לימון ושום', 'meat', false, false, '{}', '{גלוטן}', true),
  ('צלי בקר ברוטב יין',        'עיקריות בשר',    'per_weight', 180, 'ק"ג', 2,    'בישול ארוך של 8 שעות', 'meat', false, false, '{}', '{}', true),
  ('קבב בקר על האש',           'עיקריות בשר',    'per_item',    14, 'יחידה', 20,  'קבב בקר ועשבי תיבול', 'meat', false, false, '{}', '{}', true),
  ('פרגיות בתיבול מזרחי',      'עיקריות בשר',    'per_weight', 125, 'ק"ג', 2,    'בהרת, כמון ושום', 'meat', false, false, '{}', '{גלוטן}', true),
  ('מוסקה',                    'עיקריות בשר',    'per_tray',   190, 'מגש 30 ס"מ', null, 'חצילים ובשר טחון (לא זמין העונה)', 'meat', false, false, '{}', '{}', false),
  ('סלמון אפוי בעשבי תיבול',   'עיקריות דגים',   'per_weight', 165, 'ק"ג', 1,    'פילה סלמון בתנור', 'pareve', false, false, '{דגים}', '{גלוטן}', true),
  ('פילה מושט ברוטב חריף',     'עיקריות דגים',   'per_weight', 140, 'ק"ג', 1,    'ברוטב עגבניות ופלפל חריף', 'pareve', false, false, '{דגים}', '{}', true),
  ('אורז לבן עם שקדים',        'תוספות',         'per_tray',    95, 'מגש 30 ס"מ', null, 'אורז פרסי ושקדים קלויים', 'pareve', true, true, '{אגוזים}', '{גלוטן}', true),
  ('תפוחי אדמה צלויים',        'תוספות',         'per_tray',    90, 'מגש 30 ס"מ', null, 'ברוזמרין ושום', 'pareve', true, true, '{}', '{גלוטן}', true),
  ('פסטה ברוטב עגבניות',       'תוספות',         'per_tray',   105, 'מגש 30 ס"מ', null, 'פנה ברוטב עגבניות ובזיליקום', 'pareve', true, true, '{גלוטן}', '{}', true),
  ('מג''דרה',                  'תוספות',         'per_tray',    85, 'מגש 30 ס"מ', null, 'אורז, עדשים ובצל מטוגן', 'pareve', true, true, '{}', '{}', true),
  ('ירקות אנטיפסטי',           'תוספות',         'per_tray',   115, 'מגש 30 ס"מ', null, 'ירקות צלויים בשמן זית', 'pareve', true, true, '{}', '{}', true),
  ('לזניה ירקות',              'צמחוני וטבעוני', 'per_tray',   170, 'מגש 30 ס"מ', null, 'שכבות פסטה, ירקות ורוטב בשמל', 'dairy', true, false, '{גלוטן,חלב}', '{}', true),
  ('קציצות עדשים ברוטב',       'צמחוני וטבעוני', 'per_item',     8, 'יחידה', 20,  'ברוטב עגבניות', 'pareve', true, null, '{}', '{}', true),
  ('פשטידת תרד ופטה',          'צמחוני וטבעוני', 'per_tray',   150, 'מגש 30 ס"מ', null, 'תרד, פטה וביצים', 'dairy', true, false, '{חלב,ביצים,גלוטן}', '{}', true),
  ('עוגת שוקולד',              'קינוחים',        'per_tray',   140, 'מגש 30 ס"מ', null, 'עוגה בחושה פרווה', 'pareve', true, null, '{ביצים,גלוטן}', '{}', true),
  ('סלט פירות העונה',          'קינוחים',        'per_guest',   14, 'לאורח', null, 'פירות חתוכים טריים', 'pareve', true, true, '{}', '{גלוטן,חלב,ביצים,אגוזים}', true),
  ('מוס שוקולד בכוסות',        'קינוחים',        'per_item',    12, 'כוס', 20,   'מוס שוקולד מריר', 'dairy', true, false, '{חלב}', '{}', true),
  ('מגש עוגיות',               'קינוחים',        'per_tray',   110, 'מגש 30 ס"מ', null, 'עוגיות חמאה ואגוזים', null, null, null, '{גלוטן,אגוזים}', '{}', true),
  ('לחמניות טריות',            'מאפים',          'per_item',   3.5, 'יחידה', 30,  'לחמניות מחמצת', 'pareve', true, true, '{גלוטן}', '{}', true),
  ('פוקאצ''ה',                 'מאפים',          'per_tray',    60, 'מגש 30 ס"מ', null, 'פוקאצ''ה עם רוזמרין ומלח גס', 'pareve', true, true, '{גלוטן}', '{}', true);

insert into public.dishes (category_id, name, description, pricing_unit, unit_price, unit_label, min_quantity, is_available)
select c.id, d.name, d.descr, d.unit, d.price, d.label, d.min_q, d.available
from _dish d join public.dish_categories c on c.name = d.cat;

insert into public.dish_dietary (dish_id, kashrut_class, is_vegetarian, is_vegan, verified_at)
select x.id, d.kashrut, d.veg, d.vegan,
       case when d.kashrut is null then null else now() - interval '10 days' end
from _dish d join public.dishes x on x.name = d.name;

insert into public.dish_allergens (dish_id, allergen_id, status)
select x.id, a.id, 'contains'::public.allergen_status
from _dish d join public.dishes x on x.name = d.name
cross join lateral unnest(d.contains) as c(name) join public.allergens a on a.name = c.name
union all
select x.id, a.id, 'free'::public.allergen_status
from _dish d join public.dishes x on x.name = d.name
cross join lateral unnest(d.free) as f(name) join public.allergens a on a.name = f.name;

insert into public.delivery_zones (name, fee, definition) values
  ('תל אביב - יפו',            80,  '{"cities": ["תל אביב - יפו"]}'),
  ('רמת גן, גבעתיים ובני ברק', 100, '{"cities": ["רמת גן", "גבעתיים", "בני ברק"]}'),
  ('השרון',                    150, '{"cities": ["הרצליה", "רמת השרון", "רעננה", "כפר סבא"]}'),
  ('ירושלים',                  250, '{"cities": ["ירושלים", "מבשרת ציון"]}');

-- Sunday (0) to Friday (5).
insert into public.time_slots (fulfillment_type, weekday, start_time, end_time, capacity)
select ft, wd, s, e, cap
from (values ('pickup'::public.fulfillment_type, '10:00'::time, '13:00'::time, 8),
             ('pickup',   '16:00', '19:00', 8),
             ('delivery', '11:00', '14:00', 5),
             ('delivery', '17:00', '20:00', 5)) as v(ft, s, e, cap)
cross join generate_series(0, 4) as wd
union all
select 'pickup', 5, '08:00', '12:00', 10
union all
select 'delivery', 5, '09:00', '12:00', 6;

insert into public.blocked_dates (date, reason) values
  (current_date + 21, 'חופשת צוות'),
  (current_date + 22, 'חופשת צוות'),
  (current_date + 45, 'אירוע סגור'),
  (current_date + 80, 'תחזוקת מטבח');

insert into public.quantity_rules (category_id, per_adult, per_child, round_to)
select id, r.pa, r.pc, r.rt
from public.dish_categories c
join (values ('סלטים', 0.07, 0.04, 1), ('עיקריות בשר', 0.25, 0.15, 0.5),
             ('עיקריות דגים', 0.20, 0.10, 0.5), ('תוספות', 0.07, 0.05, 1),
             ('קינוחים', 0.06, 0.06, 1)) as r(cat, pa, pc, rt) on r.cat = c.name;

-- ============================================================ part 2: generator
do $$
declare
  first_names text[] := array['נועה','יוסי','מיכל','אבי','שירה','דניאל','רונית','עומר','תמר','אלון',
                              'הילה','גיא','ליאת','איתי','מאיה','רועי','קרן','אריאל','ענבל','יונתן'];
  last_names  text[] := array['כהן','לוי','מזרחי','פרץ','ביטון','אברהם','פרידמן','שפירא','אזולאי','דהן',
                              'גבאי','חדד','בן דוד','אוחיון','רוזן'];
  event_types text[] := array['בר מצווה','בת מצווה','ברית','יום הולדת','חתונה קטנה','אירוסין',
                              'אירוע חברה','שבת חתן','חנוכת בית','מסיבת יום נישואין'];
  reject_notes text[] := array['התאריך כבר מלא, אשמח להציע תאריך אחר',
                               'אין לנו משלוחים לאזור הזה בתאריך המבוקש',
                               'הכמויות קטנות מהמינימום לאירוע מסוג זה'];
  approve_notes text[] := array['מאושר, נתראה באירוע!', 'אושר. נא לאשר מספר אורחים סופי 48 שעות לפני', null];
  c record; e record; o record; d record;
  n_events int; i int; guests int; qty numeric; target text; r float;
  zone uuid; ord uuid; conv uuid; t_sub timestamptz; t_dec timestamptz;
begin
  perform setseed(0.42);

  -- 24 customers without a login (history from phone or WhatsApp orders).
  for i in 1..24 loop
    insert into public.customers (full_name, email, phone, created_at)
    values (
      first_names[1 + floor(random() * array_length(first_names, 1))::int] || ' ' ||
        last_names[1 + floor(random() * array_length(last_names, 1))::int],
      'customer' || i || '@example.com',
      '05' || (2 + floor(random() * 3))::int || '-' || lpad((floor(random() * 10000000))::int::text, 7, '0'),
      now() - make_interval(days => 30 + floor(random() * 300)::int)
    );
  end loop;

  -- Events: demo customers get 3 each, others 1-2.
  for c in select * from public.customers order by created_at loop
    n_events := case when c.auth_user_id is not null then 3 else 1 + floor(random() * 2)::int end;
    for i in 1..n_events loop
      guests := 15 + floor(random() * 120)::int;
      insert into public.events (customer_id, event_type, event_date, adults, children,
                                 vegetarian_guests, vegan_guests, restricted_guests, dietary_notes)
      values (
        c.id,
        event_types[1 + floor(random() * array_length(event_types, 1))::int],
        current_date + (floor(random() * 150) - 60)::int,
        greatest(guests - floor(random() * guests * 0.3)::int, 1),
        floor(random() * guests * 0.3)::int,
        floor(random() * guests * 0.15)::int,
        floor(random() * guests * 0.05)::int,
        floor(random() * 4)::int,
        case when random() < 0.3 then 'שני אורחים עם אלרגיה לאגוזים, נא לסמן מנות' end
      );
    end loop;
  end loop;

  -- One order per event, built as a draft and then moved through the real status flow.
  for e in select ev.*, (ev.adults + ev.children) as g from public.events ev order by ev.event_date loop
    if random() < 0.55 then
      select id into zone from public.delivery_zones order by random() limit 1;
      insert into public.orders (customer_id, event_id, fulfillment_type, requested_at, delivery_address, delivery_zone_id)
      values (e.customer_id, e.id, 'delivery', e.event_date + time '12:00',
              'רחוב הדוגמה ' || (1 + floor(random() * 120))::int, zone)
      returning id into ord;
    else
      insert into public.orders (customer_id, event_id, fulfillment_type, requested_at)
      values (e.customer_id, e.id, 'pickup', e.event_date + time '10:30')
      returning id into ord;
    end if;

    for d in select * from public.dishes where is_available order by random() limit 4 + floor(random() * 6)::int loop
      qty := case d.pricing_unit
        when 'per_guest'  then e.g
        when 'per_tray'   then ceil(e.g / 15.0)
        when 'per_weight' then round(e.g * 0.12, 1)
        else greatest(coalesce(d.min_quantity, 1), e.g * (1 + floor(random() * 2)))
      end;
      insert into public.order_items (order_id, dish_id, quantity) values (ord, d.id, greatest(qty, 1));
    end loop;

    r := random();
    target := case
      when e.event_date < current_date then case when r < 0.85 then 'approved' else 'rejected' end
      when r < 0.30 then 'draft'
      when r < 0.65 then 'pending_approval'
      when r < 0.95 then 'approved'
      else 'rejected' end;

    t_sub := least(now() - interval '2 hours', e.event_date - make_interval(days => 5 + floor(random() * 25)::int));
    t_dec := least(now() - interval '1 hour', t_sub + make_interval(hours => 1 + floor(random() * 47)::int));

    if target <> 'draft' then
      update public.orders set status = 'pending_approval', submitted_at = t_sub where id = ord;
      update public.order_status_history set created_at = t_sub
       where order_id = ord and to_status = 'pending_approval';
    end if;
    if target in ('approved', 'rejected') then
      update public.orders
         set status = target::public.order_status,
             decided_at = t_dec,
             decision_note = case when target = 'rejected'
                                  then reject_notes[1 + floor(random() * 3)::int]
                                  else approve_notes[1 + floor(random() * 3)::int] end
       where id = ord;
      update public.order_status_history
         set created_at = t_dec, changed_by = 'owner'
       where order_id = ord and to_status = target::public.order_status;
    end if;
    update public.order_status_history
       set created_at = t_sub - interval '1 day', changed_by = 'customer'
     where order_id = ord and to_status = 'draft';
    update public.order_status_history
       set changed_by = 'customer'
     where order_id = ord and to_status = 'pending_approval';
  end loop;

  -- AI conversations on about 40% of orders; drafts may get a pending proposal.
  for o in select * from public.orders where random() < 0.4 loop
    insert into public.ai_conversations (order_id, created_at)
    values (o.id, coalesce(o.submitted_at, now()) - interval '1 day')
    returning id into conv;

    insert into public.ai_messages (conversation_id, role, content, created_at) values
      (conv, 'user', jsonb_build_object('text', 'יש לכם המלצה למנה טבעונית נוספת?'),
       coalesce(o.submitted_at, now()) - interval '1 day'),
      (conv, 'assistant', jsonb_build_object('text',
         'מומלץ להוסיף קציצות עדשים ברוטב. שימו לב שהמידע על טבעונות המנה עדיין לא אומת, ולכן הוא מסומן כלא ידוע.'),
       coalesce(o.submitted_at, now()) - interval '1 day' + interval '20 seconds');

    if o.status = 'draft' and random() < 0.6 then
      select * into d from public.dishes where name = 'קציצות עדשים ברוטב';
      insert into public.ai_change_proposals
        (order_id, conversation_id, base_order_version, changes, price_before, price_after, status)
      select o.id, conv, o.version,
             jsonb_build_array(jsonb_build_object('op', 'add_item', 'dish_id', d.id, 'quantity', 30)),
             s.total, s.total + d.unit_price * 30, 'pending'
      from (select coalesce(sum(i.quantity * x.unit_price), 0) as total
              from public.order_items i join public.dishes x on x.id = i.dish_id
             where i.order_id = o.id) s;
    elsif o.status <> 'draft' and random() < 0.5 then
      insert into public.ai_change_proposals
        (order_id, conversation_id, base_order_version, changes, price_before, price_after,
         status, created_at, decided_at, executed_at)
      values (o.id, conv, greatest(o.version - 2, 1),
              '[{"op": "set_quantity", "note": "synthetic"}]', o.subtotal, o.subtotal + 120,
              (array['approved','rejected','expired'])[1 + floor(random() * 3)::int]::public.proposal_status,
              o.submitted_at - interval '1 day', o.submitted_at - interval '23 hours', null);
    end if;
  end loop;

  update public.ai_change_proposals set executed_at = decided_at where status = 'approved';
end;
$$;

-- Summary
select 'customers' as table_name, count(*) from public.customers
union all select 'events', count(*) from public.events
union all select 'orders: ' || status, count(*) from public.orders group by status
union all select 'order_items', count(*) from public.order_items
union all select 'order_status_history', count(*) from public.order_status_history
union all select 'dishes', count(*) from public.dishes
union all select 'ai_messages', count(*) from public.ai_messages
union all select 'ai_change_proposals', count(*) from public.ai_change_proposals;
