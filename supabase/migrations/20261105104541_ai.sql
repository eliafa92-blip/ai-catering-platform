-- AI assistant: conversations, messages, and change proposals.
-- Proposals never change an order by themselves; the backend applies them after the
-- customer approves, checking base_order_version against orders.version.

create table public.ai_conversations (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders (id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index ai_conversations_order_id_idx on public.ai_conversations (order_id);

create table public.ai_messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.ai_conversations (id) on delete cascade,
  role             text not null check (role in ('user', 'assistant', 'tool')),
  content          jsonb not null,
  created_at       timestamptz not null default now()
);
create index ai_messages_conversation_idx on public.ai_messages (conversation_id, created_at);

create table public.ai_change_proposals (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references public.orders (id) on delete cascade,
  conversation_id     uuid references public.ai_conversations (id) on delete set null,
  base_order_version  int not null,
  changes             jsonb not null,
  price_before        numeric(10,2) not null,
  price_after         numeric(10,2) not null,
  status              public.proposal_status not null default 'pending',
  created_at          timestamptz not null default now(),
  decided_at          timestamptz,
  executed_at         timestamptz
);
create index ai_change_proposals_order_id_idx on public.ai_change_proposals (order_id);
create index ai_change_proposals_conversation_id_idx on public.ai_change_proposals (conversation_id);
-- At most one pending proposal per order.
create unique index ai_change_proposals_one_pending
  on public.ai_change_proposals (order_id) where status = 'pending';
