"""Trade list payment filters align with derived_status (no short pages)."""

import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.main import app
from app.services.trade_purchase_service import _trade_list_payment_exprs

client = TestClient(app)


def test_trade_list_payment_exprs_keys():
    pay = _trade_list_payment_exprs(date.today())
    assert set(pay) == {"is_paid", "is_overdue", "is_due_soon", "is_pending"}


def _owner_and_item():
    u = uuid.uuid4().hex[:10]
    r = client.post(
        "/v1/auth/register",
        json={
            "username": f"pl{u}",
            "email": f"pl{u}@test.hexa.local",
            "password": "testpass12",
        },
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat{u}"},
    )
    assert cat.status_code == 201, cat.text
    sid = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup{u}", "phone": "9000000011", "gst_number": "22AAAAA0000A1Z5"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat.json()["id"],
            "name": f"Item{u} 50KG",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    return h, bid, item.json()["id"], sid


def test_pending_list_excludes_saved_draft_rows():
    h, bid, iid, sid = _owner_and_item()
    today = date.today().isoformat()
    body = {
        "purchase_date": today,
        "supplier_id": sid,
        "status": "saved",
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "Draft line",
                "qty": 1,
                "unit": "bag",
                "landing_cost": "100",
                "kg_per_unit": "50",
                "landing_cost_per_kg": "2",
            }
        ],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text
    pid = pr.json()["id"]

    pending = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        params={"status": "pending", "limit": 50},
    )
    assert pending.status_code == 200, pending.text
    ids = {row["id"] for row in pending.json()}
    assert pid not in ids

    drafts = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        params={"status": "draft", "limit": 50},
    )
    assert drafts.status_code == 200, drafts.text
    draft_ids = {row["id"] for row in drafts.json()}
    assert pid in draft_ids
