from fastapi.testclient import TestClient

import app.main as main
from app.core.config import Settings

client = TestClient(main.app)


def test_public_config_exposes_only_public_values(monkeypatch):
    settings = Settings(
        supabase_url="https://example.supabase.co",
        supabase_publishable_key="sb_publishable_test",
        supabase_secret_key="sb_secret_must_not_leak",  # noqa: S106 - fake test value
    )
    monkeypatch.setattr(main, "get_settings", lambda: settings)

    response = client.get("/api/public-config")

    assert response.status_code == 200
    assert response.json() == {
        "supabaseUrl": "https://example.supabase.co",
        "supabasePublishableKey": "sb_publishable_test",
    }
    assert "sb_secret" not in response.text


def test_login_and_order_pages_served():
    for path in ("/login/", "/order/", "/css/order.css"):
        response = client.get(path)
        assert response.status_code == 200
