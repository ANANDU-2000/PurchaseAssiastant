"""Stock alerts summary SQL aggregation matches legacy row semantics."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app
from app.services.stock_inventory import stock_status

client = TestClient(app)


def _owner_headers():
    suffix = uuid.uuid4().hex[:10]
    email = f"alerts{suffix}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"al{suffix}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _supplier_id(h, bid) -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={
            "name": f"Sup {uuid.uuid4().hex[:6]}",
            "phone": "9876504321",
            "gst_number": "22AAAAA0000A1Z5",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _create_piece_item(h, bid, sid, *, name: str, cat_id: str) -> str:
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "name": name,
            "category_id": cat_id,
            "default_unit": "piece",
            "stock_unit": "piece",
            "default_supplier_ids": [sid],
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _patch_stock(h, bid, item_id: str, qty: float, *, idem: str | None = None):
    body = {
        "new_qty": qty,
        "adjustment_type": "correction",
        "reason": "test",
    }
    if idem:
        body["idempotency_key"] = idem
    r = client.patch(
        f"/v1/businesses/{bid}/stock/{item_id}",
        headers=h,
        json=body,
    )
    assert r.status_code == 200, r.text


def _set_reorder(h, bid, item_id: str, reorder: float):
    r = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{item_id}",
        headers=h,
        json={"reorder_level": reorder},
    )
    assert r.status_code == 200, r.text


def test_stock_alerts_summary_counts():
    h, bid = _owner_headers()
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cat_id = cat.json()["id"]

    out_id = _create_piece_item(h, bid, sid, name="Out Item", cat_id=cat_id)
    client.post(
        f"/v1/businesses/{bid}/stock/{out_id}/opening-stock",
        headers=h,
        json={
            "qty": 5,
            "reason": "Initial",
            "idempotency_key": f"open:{uuid.uuid4().hex}",
        },
    ).raise_for_status()
    _patch_stock(h, bid, out_id, 0, idem=f"out:{uuid.uuid4().hex}")

    low_id = _create_piece_item(h, bid, sid, name="Low Item", cat_id=cat_id)
    _patch_stock(h, bid, low_id, 8, idem=f"low:{uuid.uuid4().hex}")
    _set_reorder(h, bid, low_id, 10)

    crit_id = _create_piece_item(h, bid, sid, name="Crit Item", cat_id=cat_id)
    _patch_stock(h, bid, crit_id, 3, idem=f"crit:{uuid.uuid4().hex}")
    _set_reorder(h, bid, crit_id, 10)

    micro_id = _create_piece_item(h, bid, sid, name="Micro Item", cat_id=cat_id)
    _patch_stock(h, bid, micro_id, 0.5, idem=f"micro:{uuid.uuid4().hex}")

    r = client.get(f"/v1/businesses/{bid}/stock/alerts/summary", headers=h)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["total_items"] == 4
    assert data["out_of_stock"] == 1
    assert data["active_out_of_stock"] == 1
    assert data["critical_stock"] == 1
    assert data["low_stock"] >= 2
    assert data["missing_usage_logs"] == 4


def test_stock_status_reference_cases():
    assert stock_status(Decimal("0"), Decimal("10")) == "out"
    assert stock_status(Decimal("4"), Decimal("10")) == "critical"
    assert stock_status(Decimal("8"), Decimal("10")) == "low"
    assert stock_status(Decimal("20"), Decimal("10")) == "healthy"
