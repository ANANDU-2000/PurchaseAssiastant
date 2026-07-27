"""Barcode lookup TTL cache (repeat scan within 30s)."""

import uuid

from fastapi.testclient import TestClient

from app.main import app
from app.routers import stock as stock_router

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"blc{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _type_id(h, bid):
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat{uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    return types.json()[0]["id"]


def test_barcode_lookup_cache_hit(monkeypatch):
    stock_router._barcode_lookup_cache.clear()
    h, bid = _owner_headers()
    tid = _type_id(h, bid)
    code = f"CACHE{uuid.uuid4().hex[:8]}"
    created = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json={
            "barcode": code,
            "item_code": f"IC-{code}",
            "name": "Cache Test Item",
            "type_id": tid,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
        },
    )
    assert created.status_code == 201, created.text

    first = client.get(
        f"/v1/businesses/{bid}/stock/barcode/lookup",
        headers=h,
        params={"code": code},
    )
    assert first.status_code == 200, first.text
    assert len(stock_router._barcode_lookup_cache) == 1

    second = client.get(
        f"/v1/businesses/{bid}/stock/barcode/lookup",
        headers=h,
        params={"code": code},
    )
    assert second.status_code == 200, second.text
    assert second.json()["item_code"] == first.json()["item_code"]
    assert len(stock_router._barcode_lookup_cache) == 1
