"""Physical count difference_qty = counted - system (audit SSOT)."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"phys{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _item(h, bid) -> str:
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
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": f"Rice {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    patch = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 20, "adjustment_type": "manual", "reason": "seed"},
    )
    assert patch.status_code == 200, patch.text
    return iid


def test_physical_count_diff_is_counted_minus_system():
    h, bid = _owner_headers()
    iid = _item(h, bid)
    before = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert before.status_code == 200
    system = Decimal(str(before.json()["current_stock"]))
    counted = system + Decimal("3")

    rec = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-count",
        headers=h,
        json={"counted_qty": float(counted), "notes": "audit test"},
    )
    assert rec.status_code == 200, rec.text
    body = rec.json()
    diff = Decimal(str(body["difference_qty"]))
    assert diff == counted - system

    listed = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={"q": body.get("item_name") or "", "per_page": 50},
    )
    assert listed.status_code == 200
    row = next((i for i in listed.json()["items"] if i["id"] == iid), None)
    assert row is not None
    if row.get("physical_stock_difference_qty") is not None:
        assert Decimal(str(row["physical_stock_difference_qty"])) == diff
