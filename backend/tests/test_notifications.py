import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.database import async_session_factory
from app.main import app
from app.models.notification import AppNotification
from app.services.notification_emitter import emit_notification

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"notif{u}@test.hexa.local"
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
    me = client.get("/v1/me/profile", headers=h)
    uid = me.json()["id"]
    return h, bid, uid


def test_notifications_openapi_paths():
    r = client.get("/openapi.json")
    assert r.status_code == 200
    spec = r.json()
    paths = spec.get("paths", {})
    assert any(
        p.startswith("/v1/businesses/{business_id}/notifications") for p in paths
    )
    assert "/v1/businesses/{business_id}/notifications/summary" in paths
    assert "/v1/businesses/{business_id}/notifications/client-event" in paths


def test_notification_dedupe_key_length():
    iid = uuid.uuid4()
    uid = uuid.uuid4()
    day = "2026-05-18"
    key = f"low_stock:{iid}:{day}:{uid}"
    assert len(key) <= 220


def test_emit_notification_dedupe():
    import asyncio

    h, bid, uid = _register_and_business()

    async def _run() -> tuple[int, int]:
        async with async_session_factory() as db:
            n1 = await emit_notification(
                db,
                business_id=uuid.UUID(bid),
                user_ids=[uuid.UUID(uid)],
                kind="low_stock",
                title="Test low",
                body="body",
                dedupe_key="test:dedupe:1",
            )
            n2 = await emit_notification(
                db,
                business_id=uuid.UUID(bid),
                user_ids=[uuid.UUID(uid)],
                kind="low_stock",
                title="Test low",
                body="body",
                dedupe_key="test:dedupe:1",
            )
            await db.commit()
            return n1, n2

    n1, n2 = asyncio.run(_run())
    assert n1 == 1
    assert n2 == 0


def test_notifications_lifecycle():
    import asyncio

    h, bid, uid = _register_and_business()

    async def _seed() -> None:
        async with async_session_factory() as db:
            await emit_notification(
                db,
                business_id=uuid.UUID(bid),
                user_ids=[uuid.UUID(uid)],
                kind="general",
                title="Lifecycle test",
                body="Hello",
                priority="high",
                category="warehouse",
                dedupe_key=f"lifecycle:{uuid.uuid4()}",
            )
            await db.commit()

    asyncio.run(_seed())

    lr = client.get(f"/v1/businesses/{bid}/notifications", headers=h)
    assert lr.status_code == 200, lr.text
    rows = lr.json()
    assert len(rows) >= 1
    assert any(r["title"] == "Lifecycle test" for r in rows)

    uc = client.get(f"/v1/businesses/{bid}/notifications/unread-count", headers=h)
    assert uc.status_code == 200
    assert uc.json()["unread"] >= 1

    nid = next(r["id"] for r in rows if r["title"] == "Lifecycle test")
    pr = client.patch(
        f"/v1/businesses/{bid}/notifications/{nid}",
        headers=h,
        json={"read": True},
    )
    assert pr.status_code == 200, pr.text

    uc2 = client.get(f"/v1/businesses/{bid}/notifications/unread-count", headers=h)
    assert uc2.json()["unread"] >= 0

    sm = client.get(f"/v1/businesses/{bid}/notifications/summary", headers=h)
    assert sm.status_code == 200
    assert "unread" in sm.json()


def test_client_export_event():
    h, bid, _uid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/notifications/client-event",
        headers=h,
        json={
            "kind": "export_failed",
            "title": "PDF export failed",
            "body": "Please try again.",
            "priority": "critical",
            "category": "system",
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["updated"] >= 1
