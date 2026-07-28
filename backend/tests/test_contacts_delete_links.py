"""Supplier/broker delete must clear broker_supplier_m2m (no ON DELETE CASCADE)."""

import asyncio
import uuid
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

from app.database import async_session_factory
from app.main import app
from app.models import TradePurchase, TradePurchaseLine

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"cdl{u}@test.hexa.local"
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
    return h, bid, u


def test_delete_supplier_with_broker_m2m_succeeds():
    h, bid, _ = _register_and_business()
    b = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": "Link Broker", "commission_type": "percent", "commission_value": 1.0},
    )
    assert b.status_code == 201, b.text
    brid = b.json()["id"]
    s = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Linked Supplier", "phone": "9000000011", "broker_ids": [brid]},
    )
    assert s.status_code == 201, s.text
    sid = s.json()["id"]

    d = client.delete(f"/v1/businesses/{bid}/suppliers/{sid}", headers=h)
    assert d.status_code == 204, d.text
    g = client.get(f"/v1/businesses/{bid}/suppliers/{sid}", headers=h)
    assert g.status_code == 404


def test_delete_broker_after_supplier_reassign_succeeds():
    """After supplier moves to another broker, old broker delete must not 500 on M2M."""
    h, bid, _ = _register_and_business()
    b1 = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": "Old Broker", "commission_type": "percent", "commission_value": 1.0},
    )
    b2 = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": "New Broker", "commission_type": "percent", "commission_value": 2.0},
    )
    assert b1.status_code == 201 and b2.status_code == 201
    brid1, brid2 = b1.json()["id"], b2.json()["id"]
    s = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Reassign Me", "phone": "9000000022", "broker_ids": [brid1]},
    )
    assert s.status_code == 201, s.text
    sid = s.json()["id"]
    p = client.patch(
        f"/v1/businesses/{bid}/suppliers/{sid}",
        headers=h,
        json={"broker_ids": [brid2]},
    )
    assert p.status_code == 200, p.text
    d = client.delete(f"/v1/businesses/{bid}/brokers/{brid1}", headers=h)
    assert d.status_code == 204, d.text


def test_supplier_metrics_avg_landing_from_line_money():
    h, bid, u = _register_and_business()
    prof = client.get("/v1/me/profile", headers=h)
    uid = uuid.UUID(prof.json()["id"])
    business_uuid = uuid.UUID(bid)

    s = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Metrics Sup", "phone": "9000000033"},
    )
    assert s.status_code == 201, s.text
    sid = uuid.UUID(s.json()["id"])

    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Metrics Cat"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Metrics Item",
            "default_unit": "kg",
            "default_supplier_ids": [str(sid)],
        },
    )
    assert item.status_code == 201, item.text
    iid = uuid.UUID(item.json()["id"])

    async def _seed() -> None:
        async with async_session_factory() as session:
            tp = TradePurchase(
                business_id=business_uuid,
                user_id=uid,
                human_id=f"PUR-M-{u}",
                purchase_date=date.today(),
                supplier_id=sid,
                total_amount=Decimal("200.00"),
                status="confirmed",
            )
            session.add(tp)
            await session.flush()
            session.add(
                TradePurchaseLine(
                    trade_purchase_id=tp.id,
                    catalog_item_id=iid,
                    item_name="Bag A",
                    qty=Decimal("2"),
                    unit="kg",
                    landing_cost=Decimal("50"),
                    selling_cost=Decimal("60"),
                    line_total=Decimal("100"),
                )
            )
            session.add(
                TradePurchaseLine(
                    trade_purchase_id=tp.id,
                    catalog_item_id=iid,
                    item_name="Bag B",
                    qty=Decimal("2"),
                    unit="kg",
                    landing_cost=Decimal("50"),
                    selling_cost=Decimal("70"),
                    line_total=Decimal("100"),
                )
            )
            await session.commit()

    asyncio.run(_seed())

    today = date.today().isoformat()
    m = client.get(
        f"/v1/businesses/{bid}/suppliers/{sid}/metrics",
        headers=h,
        params={"from": today, "to": today},
    )
    assert m.status_code == 200, m.text
    body = m.json()
    assert body["deals"] == 1
    assert abs(body["total_qty"] - 4.0) < 0.01
    assert body["purchase_amount"] > 0
    assert abs(body["avg_landing"] - (body["purchase_amount"] / body["total_qty"])) < 0.01
