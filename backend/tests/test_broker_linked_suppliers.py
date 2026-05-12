"""GET /brokers/{id}/linked-suppliers from distinct trade_purchases."""

import uuid
from datetime import date
from decimal import Decimal

import asyncio

from fastapi.testclient import TestClient

from app.database import async_session_factory
from app.main import app
from app.models import TradePurchase

client = TestClient(app)


def test_broker_linked_suppliers_two_suppliers_same_broker():
    u = uuid.uuid4().hex[:10]
    email = f"bls{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    prof = client.get("/v1/me/profile", headers=h)
    assert prof.status_code == 200, prof.text
    uid = uuid.UUID(prof.json()["id"])
    business_uuid = uuid.UUID(bid)

    bro = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": "Link Broker", "commission_type": "percent", "commission_value": 1.0},
    )
    assert bro.status_code == 201, bro.text
    brid = uuid.UUID(bro.json()["id"])

    s1 = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Linked Alpha", "phone": "9000000001"},
    )
    s2 = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Linked Beta", "phone": "9000000002"},
    )
    assert s1.status_code == 201 and s2.status_code == 201, (s1.text, s2.text)
    sid1 = uuid.UUID(s1.json()["id"])
    sid2 = uuid.UUID(s2.json()["id"])

    async def _seed() -> None:
        async with async_session_factory() as session:
            session.add_all(
                [
                    TradePurchase(
                        business_id=business_uuid,
                        user_id=uid,
                        human_id=f"PUR-L-{u}-1",
                        purchase_date=date.today(),
                        supplier_id=sid1,
                        broker_id=brid,
                        total_amount=Decimal("100.00"),
                        status="confirmed",
                    ),
                    TradePurchase(
                        business_id=business_uuid,
                        user_id=uid,
                        human_id=f"PUR-L-{u}-2",
                        purchase_date=date.today(),
                        supplier_id=sid2,
                        broker_id=brid,
                        total_amount=Decimal("200.00"),
                        status="confirmed",
                    ),
                ]
            )
            await session.commit()

    asyncio.run(_seed())

    lr = client.get(
        f"/v1/businesses/{bid}/brokers/{brid}/linked-suppliers",
        headers=h,
    )
    assert lr.status_code == 200, lr.text
    rows = lr.json()
    assert len(rows) == 2
    by_name = {x["name"]: x for x in rows}
    assert by_name["Linked Alpha"]["phone"] == "9000000001"
    assert by_name["Linked Beta"]["phone"] == "9000000002"


def test_broker_linked_suppliers_404_unknown_broker():
    u = uuid.uuid4().hex[:10]
    email = f"bls404{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    fake = uuid.uuid4()
    lr = client.get(
        f"/v1/businesses/{bid}/brokers/{fake}/linked-suppliers",
        headers=h,
    )
    assert lr.status_code == 404
