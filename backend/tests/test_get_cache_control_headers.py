"""GET Cache-Control headers on curated read endpoints."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"cc{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"cc{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_stock_list_has_private_cache_control():
    h, bid = _owner_headers()
    r = client.get(f"/v1/businesses/{bid}/stock/list", headers=h, params={"page": 1, "per_page": 1})
    assert r.status_code == 200, r.text
    assert r.headers.get("cache-control") == "private, max-age=30"


def test_home_overview_has_private_cache_control():
    h, bid = _owner_headers()
    today = date.today()
    start = today - timedelta(days=6)
    r = client.get(
        f"/v1/businesses/{bid}/reports/home-overview",
        headers=h,
        params={"from": start.isoformat(), "to": today.isoformat(), "compact": True},
    )
    assert r.status_code == 200, r.text
    assert r.headers.get("cache-control") == "private, max-age=60"


def test_catalog_items_has_private_cache_control():
    h, bid = _owner_headers()
    r = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    assert r.status_code == 200, r.text
    assert r.headers.get("cache-control") == "private, max-age=120"
