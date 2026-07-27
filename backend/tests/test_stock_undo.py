"""Stock undo-last endpoint (Sprint 12)."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"undo{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _catalog_item_id(h, bid) -> str:
    sid_r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup{uuid.uuid4().hex[:6]}"},
    )
    assert sid_r.status_code in (200, 201), sid_r.text
    sid = sid_r.json()["id"]
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
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": f"Undo rice {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
            "current_stock": 10,
            "reorder_level": 2,
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def test_undo_last_stock_change():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    before = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert before.status_code == 200
    old_qty = Decimal(str(before.json()["current_stock"]))

    patch = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 15, "adjustment_type": "manual", "reason": "test"},
    )
    assert patch.status_code == 200
    assert Decimal(str(patch.json()["current_stock"])) == Decimal("15")

    undo = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/undo-last",
        headers=h,
    )
    assert undo.status_code == 200, undo.text
    assert Decimal(str(undo.json()["current_stock"])) == old_qty
    version_after = int(undo.json().get("stock_version") or 0)
    assert version_after >= int(before.json().get("stock_version") or 0) + 1

    activity = client.get(
        f"/v1/businesses/{bid}/stock/{iid}/activity",
        headers=h,
        params={"limit": 10},
    )
    assert activity.status_code == 200
    kinds = [e.get("kind") for e in activity.json().get("activity", [])]
    assert "undo" in kinds or any("undo" in str(k) for k in kinds)


def test_owner_can_undo_after_opening_stock_set():
    """Opening-stock movements use adjustment_type opening_stock; owners may revert."""
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    before = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert before.status_code == 200
    old_qty = Decimal(str(before.json()["current_stock"]))

    set_r = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
        headers=h,
        json={"qty": 22, "reason": "opening test"},
    )
    assert set_r.status_code == 200, set_r.text
    assert Decimal(str(set_r.json()["current_stock"])) == Decimal("22")

    undo = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/undo-last",
        headers=h,
    )
    assert undo.status_code == 200, undo.text
    assert Decimal(str(undo.json()["current_stock"])) == old_qty


def test_undo_last_not_found_without_prior_change():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    resp = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/undo-last",
        headers=h,
    )
    assert resp.status_code == 404
