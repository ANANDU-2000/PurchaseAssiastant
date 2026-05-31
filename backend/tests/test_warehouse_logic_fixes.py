"""Warehouse logic audit remediation: expected qty, stock status, unit setup, commit."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app
from app.services.stock_inventory import compute_expected_system_qty, stock_status

client = TestClient(app)


def test_stock_status_near_zero_without_reorder():
    assert stock_status(Decimal("0.5"), Decimal("0")) == "low"
    assert stock_status(Decimal("0.001"), Decimal("0")) == "low"
    assert stock_status(Decimal("1"), Decimal("0")) == "healthy"
    assert stock_status(Decimal("0"), Decimal("0")) == "out"


def test_compute_expected_system_qty_includes_quick_purchase():
    expected = compute_expected_system_qty(
        Decimal("100"),
        Decimal("50"),
        total_quick_purchase_qty=Decimal("25"),
    )
    assert expected == Decimal("175")


def test_compute_expected_system_qty_full_warehouse_formula():
    """System Stock = Opening + Deliveries + Quick - Sales - Damages - Usage + Adjustments."""
    expected = compute_expected_system_qty(
        Decimal("2500"),       # opening_stock_qty: 2500 bags initial
        Decimal("500"),        # total_delivered_qty: 500 bags received via verified purchases
        total_quick_purchase_qty=Decimal("100"),  # 100 bags via quick purchase
        total_sales_qty=Decimal("800"),           # 800 bags sold
        total_damage_qty=Decimal("20"),           # 20 bags damaged
        total_usage_qty=Decimal("50"),            # 50 bags consumed/transferred
        total_manual_adjustment_qty=Decimal("10"),  # 10 bags added via manual correction
    )
    # 2500 + 500 + 100 + 10 - 800 - 20 - 50 = 2240
    assert expected == Decimal("2240")


def test_compute_expected_system_qty_no_deductions_backwards_compat():
    """When deduction params are not passed, formula still works (upper bound)."""
    expected = compute_expected_system_qty(
        Decimal("100"),
        Decimal("50"),
    )
    # 100 + 50 + 0 - 0 - 0 - 0 + 0 = 150
    assert expected == Decimal("150")


def _owner_headers():
    suffix = uuid.uuid4().hex[:10]
    email = f"whlogic{suffix}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"wl{suffix}", "email": email, "password": "testpass12"},
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


def test_stock_list_expected_includes_quick_purchase():
    h, bid = _owner_headers()
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Quick Rice",
            "default_unit": "piece",
            "stock_unit": "piece",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    opening = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
        headers=h,
        json={
            "qty": 100,
            "reason": "Initial",
            "idempotency_key": f"open:{uuid.uuid4().hex}",
        },
    )
    assert opening.status_code == 200, opening.text

    quick = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/quick-purchase",
        headers=h,
        json={
            "qty": 15,
            "supplier_id": sid,
            "idempotency_key": f"quick:{uuid.uuid4().hex}",
        },
    )
    assert quick.status_code == 200, quick.text

    listed = client.get(f"/v1/businesses/{bid}/stock/list", headers=h)
    assert listed.status_code == 200, listed.text
    row = next(i for i in listed.json()["items"] if i["id"] == iid)
    assert Decimal(str(row["expected_system_qty"])) == Decimal("115")


def _commit_purchase_pipeline(h, bid, pid, line_id):
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=h,
        json={},
    ).raise_for_status()
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "10",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ],
        },
    ).raise_for_status()
    return client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )


def test_unit_conversion_needs_setup_flag():
    """kg stock item + bag line without kg_per_bag → delta 0 + needs_unit_setup."""
    from types import SimpleNamespace

    from app.services.stock_inventory import _qty_by_catalog_item_with_skips

    line = SimpleNamespace(
        catalog_item_id=uuid.uuid4(),
        qty=Decimal("10"),
        unit="bag",
    )
    item = SimpleNamespace(
        id=line.catalog_item_id,
        name="Loose Sugar",
        stock_unit="kg",
        default_unit="kg",
        selling_unit="kg",
        default_kg_per_bag=None,
        current_stock=Decimal("0"),
    )

    async def _run():
        from unittest.mock import AsyncMock, patch

        with patch(
            "app.services.stock_inventory.fetch_catalog_items_map",
            new=AsyncMock(return_value={line.catalog_item_id: item}),
        ):
            totals, skipped = await _qty_by_catalog_item_with_skips(
                AsyncMock(), uuid.uuid4(), [line]
            )
            assert totals == {}
            assert len(skipped) == 1
            assert skipped[0]["needs_unit_setup"] is True
            assert skipped[0]["delta"] == Decimal("0")

    import asyncio

    asyncio.run(_run())


def test_delivery_commit_writes_movement_and_is_idempotent():
    h, bid = _owner_headers()
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Soap",
            "default_unit": "piece",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    purchase = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sid,
            "purchase_date": "2026-05-18",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Soap",
                    "qty": "12",
                    "unit": "piece",
                    "purchase_rate": "10",
                    "landing_cost": "10",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]
    line_id = purchase.json()["lines"][0]["id"]

    first = _commit_purchase_pipeline(h, bid, pid, line_id)
    assert first.status_code == 200, first.text
    assert any(
        Decimal(str(u["delta"])) == Decimal("12") for u in first.json().get("stock_updates", [])
    )

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("12")

    second = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )
    assert second.status_code == 200, second.text
    stock2 = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock2.json()["current_stock"])) == Decimal("12")
