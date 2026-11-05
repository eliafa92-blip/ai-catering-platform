from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.core.config import get_settings

FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"

app = FastAPI(title="AI Catering Platform")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "env": get_settings().app_env}


@app.get("/api/public-config")
def public_config() -> dict[str, str | None]:
    """Values the browser needs to talk to Supabase. Only public values: the secret key
    never leaves the server, and RLS decides what the publishable key can read."""
    settings = get_settings()
    return {
        "supabaseUrl": settings.supabase_url,
        "supabasePublishableKey": settings.supabase_publishable_key,
    }


# Mounted last so API routes take precedence.
app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")
