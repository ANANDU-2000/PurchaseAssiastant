"""Purchase damage reports: create, list, owner PATCH, pending count."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner():
    u = uuid.uuid4().hex[:8]
    email = f"dmg{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"dmg{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _setup_purchase(h, bid):
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "CatDmg"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "SupDmg", "phone": "9000000299", "gst_number": "22AAAAA0000A1Z6"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Damage Test Item",
            "default_unit": "piece",
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    p = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-06-01",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Damage Test Item",
                    "qty": "5",
                    "unit": "piece",
                    "purchase_rate": "100",
                    "landing_cost": "100",
                }
            ],
        },
    )
    assert p.status_code in (200, 201), p.text
    return p.json(), iid


def test_create_list_and_patch_damage_report():
    h, bid = _owner()
    purchase, iid = _setup_purchase(h, bid)
    pid = purchase["id"]

    create = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/damage-reports",
        headers=h,
        json={
            "catalog_item_id": iid,
            "qty_damaged": "2",
            "reason": "torn_bag",
            "unit": "bag",
            "notes": "Torn sack",
            "emit_notification": True,
            "damaged_items_in_batch": 1,
        },
    )
    assert create.status_code == 201, create.text
    body = create.json()
    assert body["status"] == "pending"
    assert body["reason"] == "torn_bag"
    assert body["item_name"] == "Damage Test Item"
    rid = body["id"]

    listed = client.get(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/damage-reports",
        headers=h,
    )
    assert listed.status_code == 200
    assert len(listed.json()) == 1

    count = client.get(
        f"/v1/businesses/{bid}/damage-reports/pending-count",
        headers=h,
    )
    assert count.status_code == 200
    assert count.json()["count"] == 1

    patch = client.patch(
        f"/v1/businesses/{bid}/damage-reports/{rid}",
        headers=h,
        json={"status": "approved"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json()["status"] == "approved"

    count2 = client.get(
        f"/v1/businesses/{bid}/damage-reports/pending-count",
        headers=h,
    )
    assert count2.json()["count"] == 0


def test_create_damage_invalid_reason():
    h, bid = _owner()
    purchase, iid = _setup_purchase(h, bid)
    pid = purchase["id"]
    bad = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/damage-reports",
        headers=h,
        json={
            "catalog_item_id": iid,
            "qty_damaged": "1",
            "reason": "not_a_reason",
        },
    )
    assert bad.status_code in (400, 422)


def test_patch_damage_invalid_status():
    h, bid = _owner()
    purchase, iid = _setup_purchase(h, bid)
    pid = purchase["id"]
    create = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/damage-reports",
        headers=h,
        json={
            "item_name": "Damage Test Item",
            "qty_damaged": "1",
            "damage_type": "damaged",
        },
    )
    assert create.status_code == 201
    rid = create.json()["id"]
    bad = client.patch(
        f"/v1/businesses/{bid}/damage-reports/{rid}",
        headers=h,
        json={"status": "pending"},
    )
    assert bad.status_code in (400, 422)
