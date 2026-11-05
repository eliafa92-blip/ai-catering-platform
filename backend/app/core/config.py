from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(".env", "../.env"), extra="ignore")

    app_env: str = "development"
    database_url: str | None = None
    supabase_url: str | None = None
    # Safe for the browser; RLS decides what it can read.
    supabase_publishable_key: str | None = None
    # Server-side only. Bypasses RLS. Never send to the browser.
    supabase_secret_key: str | None = None
    # Dev only: shared password of the demo users (backend/scripts/seed_dev.py).
    demo_user_password: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
