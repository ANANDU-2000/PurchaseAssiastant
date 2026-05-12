"""Unified search: min length 1, HSN and category matching."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_unified_search_single_char_and_hsn():
    u = uuid.uuid4().hex[:10]
    email = f"us{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "SpicesZed"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    tid = types.json()[0]["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "GST Trader", "gst_number": "27AAAAA0000A1Z5"},
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Turmeric Premium",
            "type_id": tid,
            "default_unit": "kg",
            "hsn_code": "91091299",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    # Single character (name match on Turmeric / category)
    r1 = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "t"},
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert "catalog_subcategories" in d1
    assert "recent_purchases" in d1
    ids = {x["id"] for x in d1.get("catalog_items", [])}
    assert iid in ids

    # HSN substring
    r2 = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "9109"},
    )
    assert r2.status_code == 200, r2.text
    d2 = r2.json()
    assert any(x["id"] == iid for x in d2.get("catalog_items", []))

    # Category name
    r3 = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "spice"},
    )
    assert r3.status_code == 200, r3.text
    d3 = r3.json()
    assert any(x["id"] == iid for x in d3.get("catalog_items", []))

    # GST match on supplier
    r4 = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "27aaaa"},
    )
    assert r4.status_code == 200, r4.text
    d4 = r4.json()
    assert len(d4.get("suppliers", [])) >= 1


def test_unified_search_fuzzy_typo_item_name():
    u = uuid.uuid4().hex[:10]
    email = f"ust{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Staples"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sugar Supplier"},
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "SUGAR",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    sr = client.get(f"/v1/businesses/{bid}/search", headers=h, params={"q": "suger"})
    assert sr.status_code == 200, sr.text
    data = sr.json()
    assert any(x["id"] == iid for x in data.get("catalog_items", []))


def test_unified_search_catalog_rank_prefers_token_over_alphabetical():
    """Short queries used to be ordered by SQL name only; ranking uses token similarity."""
    u = uuid.uuid4().hex[:10]
    email = f"usr{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Staples"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    tid = types.json()[0]["id"]
    sup0 = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Def sup {u}"},
    )
    assert sup0.status_code == 201, sup0.text
    sid0 = sup0.json()["id"]

    icing = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "BAKER CRAFT ICING SUGAR 1KG",
            "default_unit": "kg",
            "default_supplier_ids": [sid0],
        },
    )
    assert icing.status_code == 201, icing.text
    icing_id = icing.json()["id"]

    bulk = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "SUGAR LOOSE 50KG",
            "default_unit": "kg",
            "default_supplier_ids": [sid0],
        },
    )
    assert bulk.status_code == 201, bulk.text
    bulk_id = bulk.json()["id"]

    sr = client.get(f"/v1/businesses/{bid}/search", headers=h, params={"q": "sug"})
    assert sr.status_code == 200, sr.text
    items = sr.json().get("catalog_items", [])
    ids = [x["id"] for x in items]
    assert bulk_id in ids and icing_id in ids
    assert ids.index(bulk_id) < ids.index(icing_id)


def test_unified_search_supplier_id_boosts_trade_history():
    from datetime import date

    u = uuid.uuid4().hex[:10]
    email = f"usb{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Staples"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    tid = types.json()[0]["id"]

    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Wholesale Co"},
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]

    item_a = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "SUGAR GRADE A",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item_a.status_code == 201, item_a.text
    aid = item_a.json()["id"]

    item_b = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "SUGAR SYRUP INDUSTRIAL",
            "default_unit": "kg",
            "default_supplier_ids": [sid],
        },
    )
    assert item_b.status_code == 201, item_b.text
    bid_item = item_b.json()["id"]

    tp_body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": aid,
                "item_name": "Sugar grade A",
                "qty": 2,
                "unit": "BAG",
                "landing_cost": "2800",
                "tax_percent": "0",
                "kg_per_unit": "50",
                "landing_cost_per_kg": "28",
            }
        ],
    }
    tpr = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json=tp_body,
    )
    assert tpr.status_code == 201, tpr.text

    sr = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "sugar", "supplier_id": sid},
    )
    assert sr.status_code == 200, sr.text
    ids = [x["id"] for x in sr.json().get("catalog_items", [])]
    assert aid in ids and bid_item in ids
    assert ids.index(aid) < ids.index(bid_item)


def test_unified_search_catalog_items_include_last_supplier_and_broker_phones():
    """`_attach_last_party_names` enriches catalog hits with contact phones when ids are set."""
    import asyncio

    from sqlalchemy import update

    from app.database import async_session_factory
    from app.models.catalog import CatalogItem

    u = uuid.uuid4().hex[:10]
    email = f"uphone{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "PhoneCat"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    tid = types.json()[0]["id"]

    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Phone Sup", "phone": "9876543210"},
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]

    bro = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={
            "name": "Phone Bro",
            "phone": "9123456780",
            "commission_type": "percent",
            "commission_value": 1.0,
        },
    )
    assert bro.status_code == 201, bro.text
    bid_broker = bro.json()["id"]

    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "PhoneTestItem",
            "default_unit": "kg",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    async def _patch_catalog() -> None:
        async with async_session_factory() as session:
            await session.execute(
                update(CatalogItem)
                .where(
                    CatalogItem.id == uuid.UUID(iid),
                    CatalogItem.business_id == uuid.UUID(bid),
                )
                .values(
                    last_supplier_id=uuid.UUID(sid),
                    last_broker_id=uuid.UUID(bid_broker),
                )
            )
            await session.commit()

    asyncio.run(_patch_catalog())

    sr = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "PhoneTest"},
    )
    assert sr.status_code == 200, sr.text
    hits = [x for x in sr.json().get("catalog_items", []) if x["id"] == iid]
    assert len(hits) == 1
    row = hits[0]
    assert row.get("last_supplier_phone") == "9876543210"
    assert row.get("last_broker_phone") == "9123456780"
