"""Operational stock workflow: movements, quick purchase, activity."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    suffix = uuid.uuid4().hex[:10]
    email = f"stockflow{suffix}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"sf{suffix}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _supplier_id(h, bid, name: str = "Workflow Supplier") -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"{name} {uuid.uuid4().hex[:6]}", "phone": "9876501234"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _broker_id(h, bid) -> str:
    r = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": f"Workflow Broker {uuid.uuid4().hex[:6]}"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _catalog_item_id(h, bid, *, current_stock: int = 10) -> str:
    sid = _supplier_id(h, bid, "Default Supplier")
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Flow Cat {uuid.uuid4().hex[:6]}"},
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
            "name": f"916 RAVA 50KG {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
            "current_stock": current_stock,
            "reorder_level": 2,
        },
    )
    assert item.status_code == 201, item.text
    item_id = item.json()["id"]
    if current_stock:
        patch = client.patch(
            f"/v1/businesses/{bid}/stock/{item_id}",
            headers=h,
            json={
                "new_qty": current_stock,
                "adjustment_type": "correction",
                "reason": "test seed",
            },
        )
        assert patch.status_code == 200, patch.text
    return item_id


def test_physical_update_writes_movement_and_is_idempotent():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=150)
    before = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert before.status_code == 200, before.text
    idem = f"physical:{uuid.uuid4().hex}"

    first = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-update",
        headers=h,
        json={
            "counted_qty": 145,
            "adjustment_type": "verification",
            "reason": "Physical Count",
            "last_seen_stock_version": before.json()["stock_version"],
            "idempotency_key": idem,
        },
    )
    assert first.status_code == 200, first.text
    body = first.json()
    assert Decimal(str(body["item"]["current_stock"])) == Decimal("145")
    assert Decimal(str(body["movement"]["qty_before"])) == Decimal("150.000")
    assert Decimal(str(body["movement"]["qty_after"])) == Decimal("145.000")

    again = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-update",
        headers=h,
        json={
            "counted_qty": 145,
            "adjustment_type": "verification",
            "reason": "Physical Count",
            "idempotency_key": idem,
        },
    )
    assert again.status_code == 200, again.text
    assert again.json()["movement"]["duplicate"] is True
    latest = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(latest.json()["current_stock"])) == Decimal("145")


def test_patch_stock_rejects_correction_within_one_version_drift():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=10)
    client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 11, "adjustment_type": "correction", "reason": "prep"},
    )

    stale = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={
            "new_qty": 12,
            "adjustment_type": "correction",
            "reason": "floor",
            "last_seen_stock_version": 0,
        },
    )
    assert stale.status_code == 409, stale.text
    assert stale.json()["detail"]["code"] == "STALE_STOCK_VERSION"


def test_patch_stock_rejects_stale_stock_version():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=10)
    client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 11, "adjustment_type": "correction", "reason": "prep"},
    )

    stale = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={
            "new_qty": 12,
            "adjustment_type": "correction",
            "reason": "retry",
            "last_seen_stock_version": 0,
        },
    )
    assert stale.status_code == 409, stale.text
    assert stale.json()["detail"]["code"] == "STALE_STOCK_VERSION"


def test_physical_update_rejects_stale_stock_version():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=10)
    client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 11, "adjustment_type": "correction", "reason": "prep"},
    )

    stale = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-update",
        headers=h,
        json={
            "counted_qty": 9,
            "adjustment_type": "correction",
            "reason": "Correction",
            "last_seen_stock_version": 0,
        },
    )
    assert stale.status_code == 409, stale.text
    assert stale.json()["detail"]["code"] == "STALE_STOCK_VERSION"


def test_patch_stock_allows_verification_tolerance_within_two_versions():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=10)
    client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 11, "adjustment_type": "correction", "reason": "prep"},
    )

    ok = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={
            "new_qty": 12,
            "adjustment_type": "verification",
            "reason": "floor count",
            "last_seen_stock_version": 0,
        },
    )
    assert ok.status_code == 200, ok.text


def test_patch_stock_force_skips_stale_version():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=10)
    for qty in (11, 12, 13):
        client.patch(
            f"/v1/businesses/{bid}/stock/{iid}",
            headers=h,
            json={
                "new_qty": qty,
                "adjustment_type": "correction",
                "reason": "bump",
            },
        )

    forced = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        params={"force": "true"},
        json={
            "new_qty": 20,
            "adjustment_type": "correction",
            "reason": "forced",
            "last_seen_stock_version": 0,
        },
    )
    assert forced.status_code == 200, forced.text


def test_physical_update_verification_tolerance_within_two_versions():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=10)
    client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 11, "adjustment_type": "correction", "reason": "prep"},
    )

    ok = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-update",
        headers=h,
        json={
            "counted_qty": 9,
            "adjustment_type": "verification",
            "reason": "Physical Count",
            "last_seen_stock_version": 0,
        },
    )
    assert ok.status_code == 200, ok.text


def test_quick_purchase_requires_supplier_and_writes_activity():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid, current_stock=150)
    sid = _supplier_id(h, bid)
    broker_id = _broker_id(h, bid)
    idem = f"quick:{uuid.uuid4().hex}"

    quick = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/quick-purchase",
        headers=h,
        json={
            "qty": 20,
            "supplier_id": sid,
            "broker_id": broker_id,
            "notes": "Received at back gate",
            "idempotency_key": idem,
        },
    )
    assert quick.status_code == 200, quick.text
    body = quick.json()
    assert Decimal(str(body["item"]["current_stock"])) == Decimal("170")
    assert Decimal(str(body["movement"]["delta_qty"])) == Decimal("20.000")
    assert body["purchase_log"]["supplier_id"] == sid
    assert body["purchase_log"]["broker_id"] == broker_id

    activity = client.get(
        f"/v1/businesses/{bid}/stock/{iid}/activity",
        headers=h,
    )
    assert activity.status_code == 200, activity.text
    kinds = [row["kind"] for row in activity.json()["activity"]]
    assert "quick_purchase" in kinds
    assert "staff_purchase_log" in kinds
