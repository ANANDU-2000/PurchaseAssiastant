"""Preview / validate trade purchase endpoints (SSOT parity with create)."""

import uuid
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app
from app.services.trade_preview_service import build_trade_purchase_preview
from app.services import trade_purchase_service as tps

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"pv{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    assert br.status_code == 200, br.text
    bid = br.json()[0]["id"]
    return h, bid


def _supplier_id(h, bid, *, name: str = "PV Supplier") -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": name, "phone": "9876501234", "gst_number": "22AAAAA0000A1Z5"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _catalog_item_id(h, bid, *, name: str = "PV rice") -> str:
    sid = _supplier_id(h, bid, name=f"Def {uuid.uuid4().hex[:6]}")
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
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
            "name": name,
            "default_unit": "kg",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def _line_body(catalog_item_id: str):
    return {
        "item_name": "Rice 50KG",
        "qty": "10",
        "unit": "BAG",
        "landing_cost": "100",
        "tax_percent": "5",
        "kg_per_unit": "50",
        "landing_cost_per_kg": "2",
        "catalog_item_id": catalog_item_id,
    }


def test_preview_lines_matches_create_totals():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    pd = date.today().isoformat()
    body = {
        "purchase_date": pd,
        "payment_days": 7,
        "supplier_id": sid,
        "status": "confirmed",
        "lines": [_line_body(iid)],
    }
    pr = client.post(
        f"/v1/businesses/{bid}/trade-purchases/preview-lines",
        headers=h,
        json=body,
    )
    assert pr.status_code == 200, pr.text
    pv = pr.json()

    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    saved = cr.json()

    assert Decimal(str(pv["total_amount"])) == Decimal(str(saved["total_amount"]))
    assert Decimal(str(pv["total_qty"])) == Decimal(str(saved["total_qty"]))
    assert len(pv["lines"]) == len(saved["lines"])
    assert Decimal(str(pv["lines"][0]["line_total"])) == Decimal(str(saved["lines"][0]["line_total"]))
    assert "resolved_labels" in pv["lines"][0]
    assert pv["lines"][0]["resolved_labels"].get("selling_unit")


def test_preview_errors_skip_gross_when_for_preview():
    """Relaxed preview validation must not block on line gross while typing."""
    from unittest.mock import patch

    from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn

    li = TradePurchaseLineIn(
        catalog_item_id=uuid.uuid4(),
        item_name="Test",
        qty=Decimal("1"),
        unit="kg",
        landing_cost=Decimal("10"),
    )
    body = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        status="draft",
        lines=[li],
    )
    with patch("app.services.trade_purchase_service._line_gross_base", return_value=Decimal("0")):
        prev = tps.collect_trade_purchase_preview_errors(body)
        full = tps.collect_trade_purchase_validation_errors(body)
    assert prev == [], prev
    assert any("gross" in (e.get("msg") or "").lower() for e in full), full


def test_validate_endpoint_matches_full_validation():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 7,
        "supplier_id": sid,
        "status": "confirmed",
        "lines": [
            {
                "item_name": "   ",
                "qty": "1",
                "unit": "kg",
                "landing_cost": "10",
                "catalog_item_id": iid,
            }
        ],
    }
    vr = client.post(
        f"/v1/businesses/{bid}/trade-purchases/validate",
        headers=h,
        json=body,
    )
    assert vr.status_code == 200, vr.text
    data = vr.json()
    assert data["ok"] is False
    assert data["errors"]
    assert data["warnings"] == []


def test_build_preview_matches_compute_totals_service():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 7,
        "supplier_id": sid,
        "status": "confirmed",
        "lines": [_line_body(iid)],
    }
    r = client.post(
        f"/v1/businesses/{bid}/trade-purchases/preview-lines",
        headers=h,
        json=body,
    )
    assert r.status_code == 200, r.text
    api = r.json()
    from app.schemas.trade_purchases import TradePurchaseCreateRequest

    req = TradePurchaseCreateRequest.model_validate(body)
    built = build_trade_purchase_preview(req)
    qty, amt = tps.compute_totals(req)
    assert built.total_amount == amt
    assert built.total_qty == qty
    assert len(built.lines) == len(api["lines"])
