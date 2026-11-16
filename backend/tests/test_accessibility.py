from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

STATEMENT = "/accessibility/"


def test_statement_page_served_in_hebrew_rtl():
    response = client.get(STATEMENT)
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    html = response.text
    assert '<html lang="he" dir="rtl">' in html
    assert "<h1" in html and "הצהרת נגישות" in html
    # Skip link target must exist.
    assert 'href="#main"' in html and 'id="main"' in html


def test_statement_linked_from_every_public_entry_point():
    for path in ("/", "/customer/"):
        assert f'href="{STATEMENT}"' in client.get(path).text, path


def test_required_form_fields_are_marked_in_markup_source():
    """The Hebrew 'required' marker must stay next to the fields the validators require."""
    event = client.get("/js/customer/views/event.js").text
    summary = client.get("/js/customer/views/summary.js").text
    assert "(חובה)" in event and "aria-required" in event
    assert "(חובה)" in summary and "aria-required" in summary
