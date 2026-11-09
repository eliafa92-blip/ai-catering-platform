# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Ordering and management web app for a **single catering business** (brand: yumm.ai). Customers plan a private event, pick dishes, see a price, and send a quotation request; the owner approves or rejects every request. An AI assistant may only *propose* changes that the customer approves. Specs live in `docs/` (PRD, ARCHITECTURE, DATABASE_SCHEMA, API_CONTRACTS, AI_AGENT_DESIGN, UX_UI_SPEC, OPEN_DECISIONS, ADR/) and `PRODUCT.md`. Check `docs/OPEN_DECISIONS.md` before settling anything marked open.

## Commands

All Python commands run from `backend/` with uv:

```bash
cd backend
uv sync                                    # install (CI uses: uv sync --frozen)
uv run uvicorn app.main:app --reload       # serves API + frontend on :8000
uv run ruff check .                        # lint (CI)
uv run ruff format --check .               # format check (CI)
uv run pytest                              # all tests (CI)
uv run pytest tests/test_public_config.py::test_login_and_order_pages_served   # one test
uv run python scripts/seed_dev.py          # rebuild dev data + demo users (dev Supabase only)
```

Supabase (CLI v3, **hosted dev project only, there is no local stack**; commands default to local, so always pass `--remote`):

```bash
supabase migration new <name>              # never hand-name migration files
supabase db push --remote --dry-run
supabase db push --remote --yes
supabase db advisors --remote              # run after schema/RLS changes
supabase db query --remote --read-only "select ..."
```

Config comes from the repo-root `.env` (template: `.env.example`), loaded by `backend/app/core/config.py`.

## Architecture

**One FastAPI process serves everything.** `backend/app/main.py` defines `/health` and `/api/public-config`, then mounts `frontend/` as static files at `/` (mounted last so API routes win). Frontend is plain HTML/CSS/ES modules, no build step, no framework. Same origin, so no CORS.

**Planned vs. current data path.** The docs/ADRs describe a layered backend (`api → services → repositories → models`, plus isolated `agents/` that may only call services) with SQLAlchemy and backend-authoritative pricing. Those packages are still empty. Today the browser talks **directly to Supabase** with the publishable key from `/api/public-config` (`frontend/js/supabase.js`, supabase-js pinned from jsDelivr), and **RLS is the real authorization layer**. When adding backend features, follow the ADRs (pricing and proposal execution in `services/`, AI never writes to the DB).

**Database (`supabase/migrations/`)** — key rules enforced in Postgres, not app code:
- Roles: `anon` reads the catalog only; customers own rows via `private.current_customer_id()`; owner is `app_metadata.role = 'owner'` via `private.is_owner()` (never use `user_metadata` for auth); the secret key bypasses RLS.
- Default privileges are revoked; every table gets explicit `GRANT`s plus RLS. New tables need both.
- Order lifecycle is enforced by triggers in the `private` schema: status transitions are validated, `version` is bumped, and on `draft → pending_approval` the price snapshot and totals are frozen; every status change is written to `order_status_history`. Customers may only update their own `draft` orders; the owner acts on `pending_approval`.
- `auth.users` insert trigger creates a `customers` row (except for the owner).
- Storage bucket `dish-images` (public read, owner-only write); `dishes.image_path` holds the object path.
- Realtime on orders, order_items, order_status_history, ai_messages, ai_change_proposals, dishes, blocked_dates (RLS applies to subscriptions).
- `supabase/seed.sql` is deterministic (`setseed`) and wipes data while keeping demo users; `scripts/seed_dev.py` refuses to run unless `APP_ENV=development` and `SUPABASE_URL` matches the linked project ref.

**Frontend pages** — two styles coexist:
- Illustrated yumm.ai UI (Hebrew RTL): `/` landing and `/customer/` ordering flow (`js/customer/`: `store.js` state, `views/` per step, `components/`). It currently runs on **`js/customer/mock-backend.js`**, not Supabase.
- Supabase-connected pages, styled under `<body class="plain">` (scoped rules at the end of `css/base.css` so they don't leak into the illustrated UI): `/login/`, `/order/` (real ordering flow, Hebrew RTL, `css/order.css`), `/orders/` (customer's orders, live via Realtime), `/admin/` (owner approve/reject).
- `homeFor()` in `js/supabase.js` routes owner → `/admin/`, customers → `/orders/`.

Product rules the UI must keep (from PRODUCT.md / PRD): Hebrew only and RTL with logical CSS properties; a pending quotation is never shown as a confirmed order; unknown allergen data is never shown as safe; WCAG 2.2 AA (44px targets, `aria-live` on totals and chat), respect `prefers-reduced-motion`. Dish names, prices and the mascot are mock/unlicensed; don't fabricate real business content.

## Project rules

1. **Plan before executing.** Plan every significant task before writing code; don't start coding until it's clear what is wanted. Prefer Opus for planning and Sonnet for execution.
2. **E2E and regression tests after writing code, before the next phase.**
   - E2E: run the full flow the way a real user would use the system.
   - Regression: confirm the change didn't break what already worked.
   - If tests fail, fix and rerun them before moving on.
3. **Security review** after significant code changes: run the `security-review` skill, report what it finds, and fix as needed.
4. **Obsidian documentation.** Every new project gets its own documentation in Obsidian. When a phase that involved writing code ends, update it briefly with what was done, what changed, what was tested, and what's next. Never store passwords, API keys or other secrets there.
5. **Progress page (HTML).** Keep a simple HTML file showing which development phase the project is in, and update it as the project advances. Each phase gets at most 3 lines of plain-language explanation, with no mention of development technologies. The current phase must be clearly highlighted.

## Workflow

- Branches: `main` = production, `dev` = integration. Feature work → PR into `dev`; release → PR `dev → main`. CI (`.github/workflows/`) runs ruff + pytest on pushes/PRs to both.
- Production deploys (Railway, `Dockerfile`, `railway.json` healthcheck `/health`) are manual and need explicit approval. Railway is not connected yet.
- A collaborator repo exists as git remote `jonathan` (JonathanZouari/ai-catering-platform); its `feat/supabase-foundation` branch is a competing Supabase schema that has not been merged.
