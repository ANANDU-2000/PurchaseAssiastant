"""Scheduled notification scans (evening physical reminder dedupe)."""

import asyncio
import uuid

from fastapi.testclient import TestClient

from app.database import async_session_factory
from app.main import app
from app.services.scheduled_notification_jobs import run_evening_physical_count_reminder

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
    return h, bid


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
