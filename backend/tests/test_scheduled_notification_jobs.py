"""Scheduled notification scans (evening physical reminder dedupe)."""

import asyncio
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi.testclient import TestClient

from app.database import async_session_factory
from app.main import app
from app.models import TradePurchase
from app.services.scheduled_notification_jobs import (
    run_evening_physical_count_reminder,
    run_idle_delivery_notification_scan,
)

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"sched{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid, u


def test_evening_physical_reminder_dedupes_per_day():
    _register_and_business()

    async def _run() -> tuple[int, int]:
        async with async_session_factory() as db:
            n1 = await run_evening_physical_count_reminder(db)
            n2 = await run_evening_physical_count_reminder(db)
            return n1, n2

    n1, n2 = asyncio.run(_run())
    assert n1 >= 1
    assert n2 == 0


def test_idle_delivery_scan_skips_cancelled_purchases():
    h, bid, u = _register_and_business()
    prof = client.get("/v1/me/profile", headers=h)
    uid = uuid.UUID(prof.json()["id"])
    business_uuid = uuid.UUID(bid)
    s = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Idle Sup", "phone": "9000000088"},
    )
    assert s.status_code == 201, s.text
    sid = uuid.UUID(s.json()["id"])

    async def _seed() -> None:
        async with async_session_factory() as session:
            session.add(
                TradePurchase(
                    business_id=business_uuid,
                    user_id=uid,
                    human_id=f"PUR-IDLE-{u}",
                    purchase_date=datetime.now(timezone.utc).date(),
                    supplier_id=sid,
                    total_amount=Decimal("100.00"),
                    status="cancelled",
                    delivery_status="dispatched",
                    dispatched_at=datetime.now(timezone.utc) - timedelta(hours=5),
                )
            )
            await session.commit()

    asyncio.run(_seed())

    async def _scan() -> int:
        async with async_session_factory() as db:
            return await run_idle_delivery_notification_scan(db)

    assert asyncio.run(_scan()) == 0
