"""GET /stock/{item_id}/bundle — sequential session (no shared-session gather 500)."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"sb{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _catalog_item_id(h, bid) -> str:
    sid = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup{uuid.uuid4().hex[:6]}"},
    )
    assert sid.status_code in (200, 201), sid.text
    supplier_id = sid.json()["id"]
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
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": f"Bundle item {uuid.uuid4().hex[:6]}",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [supplier_id],
            "current_stock": 10,
            "reorder_level": 2,
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def test_stock_item_bundle_returns_expected_keys():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    today = date.today()
    start = (today - timedelta(days=30)).isoformat()
    end = today.isoformat()
    r = client.get(
        f"/v1/businesses/{bid}/stock/{iid}/bundle",
        headers=h,
        params={"period_start": start, "period_end": end},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body.keys()) >= {
        "detail",
        "activity",
        "intelligence",
        "catalog_snapshot",
    }
    assert body["detail"] is not None
    assert body["detail"].get("id") == iid or body["detail"].get("item_id") == iid
    assert body["catalog_snapshot"] is not None
    assert body["activity"] is not None
    assert body["intelligence"] is not None


def test_stock_item_bundle_ok_without_period_params():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    r = client.get(f"/v1/businesses/{bid}/stock/{iid}/bundle", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    for key in ("detail", "activity", "intelligence", "catalog_snapshot"):
        assert key in body
