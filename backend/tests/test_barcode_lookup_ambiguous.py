"""Ambiguous barcode lookup returns 409 (do not silently pick one)."""

import asyncio
import uuid

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.database import async_session_factory
from app.main import app
from app.models import CatalogItem
from app.routers import stock as stock_router

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"amb{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _type_id(h, bid):
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat{uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    return types.json()[0]["id"]


async def _force_shared_barcode(
    business_id: uuid.UUID, item_ids: list[uuid.UUID], shared: str
) -> None:
    async with async_session_factory() as db:
        rows = (
            await db.execute(
                select(CatalogItem).where(
                    CatalogItem.business_id == business_id,
                    CatalogItem.id.in_(item_ids),
                )
            )
        ).scalars().all()
        assert len(rows) == 2
        for row in rows:
            row.barcode = shared
        await db.commit()


def test_barcode_lookup_ambiguous_409():
    stock_router._barcode_lookup_cache.clear()
    h, bid = _owner_headers()
    tid = _type_id(h, bid)
    shared = f"AMB{uuid.uuid4().hex[:10]}"

    a = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json={
            "barcode": f"{shared}-A",
            "item_code": f"IC-A-{shared}",
            "name": "Ambiguous A",
            "type_id": tid,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
        },
    )
    b = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json={
            "barcode": f"{shared}-B",
            "item_code": f"IC-B-{shared}",
            "name": "Ambiguous B",
            "type_id": tid,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
        },
    )
    assert a.status_code == 201, a.text
    assert b.status_code == 201, b.text
    id_a = uuid.UUID(a.json()["id"])
    id_b = uuid.UUID(b.json()["id"])
    bid_uuid = uuid.UUID(bid)

    asyncio.run(_force_shared_barcode(bid_uuid, [id_a, id_b], shared))

    stock_router._barcode_lookup_cache.clear()
    lookup = client.get(
        f"/v1/businesses/{bid}/stock/barcode/lookup",
        headers=h,
        params={"code": shared},
    )
    assert lookup.status_code == 409, lookup.text
    assert "ambiguous" in str(lookup.json().get("detail", "")).lower()
