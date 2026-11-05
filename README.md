# AI Catering Platform

Ordering and management web app for a **single catering business**. Customers plan private events, pick dishes, get backend-calculated quantities and prices, and chat with an AI assistant whose suggested changes only apply after the customer approves them. The business owner manages the catalog and approves or rejects every quotation.

> Status: **Phase 1 — scaffolding**. No business features yet. See `docs/` for the specs.

## Stack

| Layer | Tech |
|---|---|
| Backend | Python 3.12+, FastAPI, Pydantic (SQLAlchemy added in Phase 2) |
| Frontend | Plain HTML, CSS, JavaScript (served by FastAPI) |
| Data | Supabase (Postgres, Storage, Auth when approved) |
| Hosting | Railway (Dockerfile build) |
| Quality | pytest, Ruff, GitHub Actions |

## Repository layout

```
backend/        FastAPI app (api, core, models, schemas, services, repositories, agents) + tests
frontend/       customer/ and admin/ pages, css/, js/, assets/
supabase/       Supabase CLI project: migrations/ (schema, RLS, Storage, Realtime) and seed.sql
docs/           PRD, architecture, schema, API, AI agent, UX/UI, ADRs, open decisions
.github/        CI workflow
Dockerfile      Production image used by Railway
railway.json    Railway build/deploy config (healthcheck /health)
.env.example    Environment variable template
```

## Local development

Requires [uv](https://docs.astral.sh/uv/) (it installs a matching Python automatically).

```bash
cp .env.example .env          # fill values when needed; .env is git-ignored
cd backend
uv sync                       # install dependencies
uv run uvicorn app.main:app --reload
```

- API health: http://127.0.0.1:8000/health
- Customer UI: http://127.0.0.1:8000/customer/
- Admin UI: http://127.0.0.1:8000/admin/

### Tests and lint

```bash
cd backend
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

## Dependencies and why

| Package | Why |
|---|---|
| `fastapi` | Mandated web framework |
| `uvicorn[standard]` | ASGI server for FastAPI |
| `pydantic-settings` | Typed config from environment variables |
| `pytest` (dev) | Mandated test runner |
| `httpx` (dev) | Needed by FastAPI's `TestClient` |
| `ruff` (dev) | Mandated linter/formatter |

The browser loads `supabase-js` (pinned, from jsDelivr) for login, data access through RLS and Realtime. `httpx` is also used by the dev seed script.

## Branches and environments

| Branch | Purpose | Railway env | Supabase project |
|---|---|---|---|
| `main` | Production (default branch) | `production` | prod project |
| `dev` | Integration | `development` | dev project |

- Feature work → PR into `dev` (CI must pass).
- Release → PR `dev` → `main`.
- Production deploys are manual and need explicit approval.
- Each Railway environment holds its own variables from `.env.example`. **Never commit secrets.** The service-role key stays server-side.

## Supabase (database, auth, storage, realtime)

The schema lives in `supabase/migrations/` and is applied to the hosted **dev** project with the Supabase CLI (v3). There is no local Supabase stack.

```bash
supabase link <dev-project-ref>                # once
supabase db push --remote --dry-run            # see what would change
supabase db push --remote --yes                # apply new migrations
supabase db advisors --remote                  # security and performance checks
```

What the migrations set up:

- **18 tables** (see `docs/DATABASE_SCHEMA.md`), with prices frozen and status history logged by triggers when an order is submitted, approved or rejected.
- **RLS on every table.** Anonymous visitors read the catalog. Customers read and edit only their own events and draft orders. The business owner (`app_metadata.role = "owner"`) reads everything, writes the catalog and approves or rejects orders. The backend's secret key bypasses RLS.
- **Storage:** public bucket `dish-images` (JPEG/PNG/WebP, 5 MB). Only the owner can upload. `dishes.image_path` holds the object path.
- **Realtime** on `orders`, `order_items`, `order_status_history`, `ai_messages`, `ai_change_proposals`, `dishes`, `blocked_dates`. RLS applies, so customers only receive their own changes.

### Synthetic data and demo users (dev only)

```bash
cd backend
uv run python scripts/seed_dev.py
```

This creates the demo users (`owner@example.com`, `dana@`, `yossi@`, `noa@`, `avi@example.com`, all with the password in `DEMO_USER_PASSWORD`), wipes and rebuilds the data from `supabase/seed.sql`, and uploads a placeholder photo for each dish. It refuses to run unless `APP_ENV=development` and `SUPABASE_URL` matches the linked project.

Sign in at http://127.0.0.1:8000/login/.

Railway is not connected yet (planned for Phase 6).

## Documentation

- [PRD](docs/PRD.md) · [Architecture](docs/ARCHITECTURE.md) · [Database schema](docs/DATABASE_SCHEMA.md) · [API contracts](docs/API_CONTRACTS.md)
- [AI agent design](docs/AI_AGENT_DESIGN.md) · [UX/UI spec](docs/UX_UI_SPEC.md) · [Open decisions](docs/OPEN_DECISIONS.md) · [ADRs](docs/ADR/)
