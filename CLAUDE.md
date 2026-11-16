# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Ordering and management web app for a **single catering business** (brand: yumm.ai). Customers plan a private event, pick dishes, see a price, and send a quotation request; the owner approves or rejects every request. An AI assistant may only *propose* changes that the customer approves. Specs live in `docs/` (PRD, ARCHITECTURE, DATABASE_SCHEMA, API_CONTRACTS, AI_AGENT_DESIGN, UX_UI_SPEC, OPEN_DECISIONS, ADR/) and `PRODUCT.md`. Check `docs/OPEN_DECISIONS.md` before settling anything marked open.

## Commands

All Python commands run from `backend/` with uv:

```bash
cp .env.example .env                       # repo root; config reads .env or ../.env
cd backend
uv sync                                    # install (CI uses: uv sync --frozen)
uv run uvicorn app.main:app --reload       # serves API + frontend on :8000
uv run ruff check .                        # lint (rules E,F,I,B,UP,S; line length 100)
uv run ruff format --check .               # format check (CI)
uv run pytest                              # all tests (CI)
uv run pytest tests/test_public_config.py::test_login_and_order_pages_served   # one test
uv run python scripts/seed_dev.py          # rebuild dev data + demo users (dev Supabase only)
```

The frontend has no build step. Edit files under `frontend/` and reload the page.

Supabase (CLI v3, **hosted dev project only, there is no local stack**; commands default to local, so always pass `--remote`):

```bash
supabase migration new <name>              # never hand-name migration files
supabase db push --remote --dry-run
supabase db push --remote --yes
supabase db advisors --remote              # run after schema/RLS changes
supabase db query --remote --read-only "select ..."
```

Config comes from the repo-root `.env` (template: `.env.example`), loaded by `backend/app/core/config.py` (`get_settings()` is `lru_cache`d).

## Architecture

**One FastAPI process serves everything.** `backend/app/main.py` defines `/health` and `/api/public-config`, then mounts `frontend/` as static files at `/` (mounted last so API routes win). Frontend is plain HTML/CSS/ES modules, no build step, no framework. Same origin, so no CORS. The Dockerfile copies `backend/` and `frontend/` side by side; deployment target is Railway (`railway.json`, healthcheck `/health`).

**Planned vs. current data path.** The docs/ADRs describe a layered backend (`api → services → repositories → models`, plus isolated `agents/` that may only call services) with SQLAlchemy and backend-authoritative pricing. Those packages are still mostly empty scaffolds (see the phase plan in `docs/ARCHITECTURE.md`). Today the browser talks **directly to Supabase** with the publishable key from `/api/public-config` (`frontend/js/supabase.js`, supabase-js pinned from jsDelivr), and **RLS is the real authorization layer**. When adding backend features, follow the ADRs/AI_AGENT_DESIGN.md non-negotiable rules instead:
- Prices, quantities and order state are computed **only in `services/`**; the frontend and the LLM display or request them, never compute them authoritatively.
- `agents/` calls typed service functions, never the DB directly. The AI can only create `ai_change_proposals`; a proposal is executed only through a customer HTTP endpoint after the customer approves a visible diff, never by an AI tool.
- Order mutations use optimistic locking (`orders.version`); proposals are single-use (`executed_at`).
- AI never writes to the DB directly, and a pending quotation is never presented as a confirmed order.

**Database (`supabase/migrations/`)** — key rules enforced in Postgres, not app code:
- Roles: `anon` reads the catalog only; customers own rows via `private.current_customer_id()`; owner is `app_metadata.role = 'owner'` via `private.is_owner()` (never use `user_metadata` for auth); the secret key bypasses RLS.
- Default privileges are revoked; every table gets explicit `GRANT`s plus RLS. New tables need both.
- Order lifecycle is enforced by triggers in the `private` schema: status transitions are validated, `version` is bumped, and on `draft → pending_approval` the price snapshot and totals are frozen; every status change is written to `order_status_history`. Customers may only update their own `draft` orders; the owner acts on `pending_approval`.
- `auth.users` insert trigger creates a `customers` row (except for the owner).
- Storage bucket `dish-images` (public read, owner-only write); `dishes.image_path` holds the object path.
- Realtime on orders, order_items, order_status_history, ai_messages, ai_change_proposals, dishes, blocked_dates (RLS applies to subscriptions).
- `supabase/seed.sql` is deterministic (`setseed`) and wipes data while keeping demo users; `scripts/seed_dev.py` refuses to run unless `APP_ENV=development` and `SUPABASE_URL` matches the linked project ref.

**Frontend pages** — two styles coexist:
- Illustrated yumm.ai UI (Hebrew RTL): `/` landing (`js/landing.js`) and `/customer/` ordering flow. `js/customer/main.js` routes between views (`event → menu → summary → status`); `store.js` holds state (persisted to `localStorage`, bumps `order.version` on every mutation, subscribers re-render); `views/` and `components/` render into the DOM. It currently runs on **`js/customer/mock-backend.js`**, a UI-only stand-in that mirrors the shapes in `docs/API_CONTRACTS.md` so views can be switched to `js/api.js` without markup changes — values marked PLACEHOLDER are not business rules. Demo shortcut: `/customer/?demo=pending|approved|rejected` (or `#demo-pending`); `?occasion=<type>` preselects the event type.
- Supabase-connected pages, styled under `<body class="plain">` (scoped rules at the end of `css/base.css` so they don't leak into the illustrated UI): `/login/`, `/order/` (real ordering flow, Hebrew RTL, `css/order.css`), `/orders/` (customer's orders, live via Realtime), `/admin/` (owner approve/reject, live via Realtime).
- `homeFor()` in `js/supabase.js` routes owner → `/admin/`, customers → `/orders/`.
- `/accessibility/` is the accessibility statement, styled with the illustrated landing design since it's linked from the public footer. It is a **draft**: every `<mark class="todo">` is a fact only the business owner can supply (contact details, coordinator, exemption status, last-reviewed date) — do not remove those marks or invent the values.

Product rules the UI must keep (from PRODUCT.md / PRD): Hebrew only and RTL with logical CSS properties; a pending quotation is never shown as a confirmed order; unknown allergen data is never shown as safe; WCAG 2.2 AA (44px targets, `aria-live` on totals, chat and status/Realtime updates — `js/lib/announce.js`), respect `prefers-reduced-motion`. Visual identity rules are in `docs/VISUAL_IDENTITY.md`. Dish names, prices and the mascot are mock/unlicensed; don't fabricate real business content, photography, logos or testimonials.

## Project rules

1. **Plan before executing.** Plan every significant task before writing code; don't start coding until it's clear what is wanted. Prefer Opus for planning and Sonnet for execution.
2. **E2E and regression tests after writing code, before the next phase.**
   - E2E: run the full flow the way a real user would use the system.
   - Regression: confirm the change didn't break what already worked. For a frontend change, also load the affected page(s) in the running app and check the flow still works, not just `pytest`.
   - If tests fail, fix and rerun them before moving on.
3. **Security review** after significant code changes: run the `security-review` skill, report what it finds, and fix as needed. Pay particular attention to auth/RLS, secrets (the service-role/secret key must stay server-side), input validation at API boundaries, and anything that would let the AI mutate orders without customer approval.
4. **Obsidian documentation.** Every new project gets its own documentation in Obsidian. When a phase that involved writing code ends, update it briefly with what was done, what changed, what was tested, and what's next. Never store passwords, API keys or other secrets there.
5. **Progress page (HTML).** Keep a simple HTML file showing which development phase the project is in, and update it as the project advances. Each phase gets at most 3 lines of plain-language explanation, with no mention of development technologies. The current phase must be clearly highlighted.

## Workflow

- Branches: `main` = production, `dev` = integration. Feature work → PR into `dev`; release → PR `dev → main`. CI (`.github/workflows/`) runs ruff + pytest on pushes/PRs to both. Never push directly to `main`.
- Commit `uv.lock` changes together with any `pyproject.toml` change.
- Production deploys (Railway, `Dockerfile`, `railway.json` healthcheck `/health`) are manual and need explicit approval. Railway is not connected yet.
- A collaborator repo exists as git remote `jonathan` (JonathanZouari/ai-catering-platform). Its branches move independently and have repeatedly done overlapping work (its own Supabase schema on `feat/supabase-foundation`, its own accessibility pass on `dev`) — check for conflicts before merging, and don't assume a fact (e.g. "the DB exists") without checking which branch you're actually on.
