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
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Turmeric Premium",
            "type_id": tid,
            "default_unit": "kg",
            "hsn_code": "91091299",
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "GST Trader", "gst_number": "27AAAAA0000A1Z5"},
    )
    assert sup.status_code == 201, sup.text

    # Single character (name match on Turmeric / category)
    r1 = client.get(
        f"/v1/businesses/{bid}/search",
        headers=h,
        params={"q": "t"},
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
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
