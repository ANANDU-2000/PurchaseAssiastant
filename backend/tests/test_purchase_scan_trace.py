import asyncio
import uuid

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.database import async_session_factory
from app.main import app
from app.models import PurchaseScanTrace
from app.services.scanner_v2 import pipeline as scanner_v2_pipeline

client = TestClient(app)


def _register_catalog_for_scan():
    u = uuid.uuid4().hex[:10]
    r = client.post(
        "/v1/auth/register",
        json={"username": f"scan{u}", "email": f"scan{u}@test.hexa.local", "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Surag"},
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Staples"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Sugar 50 KG",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    return h, bid


def test_scan_v2_persists_raw_and_normalized_trace(monkeypatch):
    h, bid = _register_catalog_for_scan()

    async def fake_image_parse(*, image_bytes, settings, db):
        return (
            {
                "supplier_name": "Surag",
                "broker_name": None,
                "items": [
                    {
                        "name": "Sugar 50 KG",
                        "unit_type": "BAG",
                        "weight_per_unit_kg": 50,
                        "bags": 100,
                        "qty": 100,
                        "purchase_rate": 57,
                        "selling_rate": 58,
                    }
                ],
                "charges": {"delivered_rate": 56},
                "broker_commission": None,
                "payment_days": 7,
            },
            {
                "provider_used": "openai_image",
                "model_used": "gpt-test",
                "extraction_duration_ms": 123,
                "token_usage": {"total_tokens": 321},
                "failover": [{"provider": "openai_image", "ok": True}],
            },
        )

    monkeypatch.setattr(scanner_v2_pipeline, "_openai_parse_scanner_image_payload", fake_image_parse)

    res = client.post(
        "/v1/me/scan-purchase-v2",
        headers=h,
        params={"business_id": bid},
        files={"image": ("bill.jpg", b"fake-image", "image/jpeg")},
    )
    assert res.status_code == 200, res.text
    scan = res.json()

    async def load_trace():
        async with async_session_factory() as db:
            q = await db.execute(
                select(PurchaseScanTrace).where(PurchaseScanTrace.scan_token == scan["scan_token"])
            )
            return q.scalar_one()

    trace = asyncio.run(load_trace())
    assert str(trace.business_id) == bid
    assert trace.provider == "openai_image"
    assert trace.model == "gpt-test"
    assert trace.raw_response_json["supplier_name"] == "Surag"
    assert trace.normalized_response_json["scan_token"] == scan["scan_token"]
    assert trace.meta_json["token_usage"]["total_tokens"] == 321
    assert trace.image_bytes_in == len(b"fake-image")
