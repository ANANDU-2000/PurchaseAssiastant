import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _setup():
    u = uuid.uuid4().hex[:10]
    email = f"stock{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"su{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Grains"},
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Everest", "phone": "9000000001", "gst_number": "22AAAAA0000A1Z5"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Sugar 50KG",
            "item_code": f"ITM{u[:6].upper()}",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    return h, bid, item.json()["id"]


def test_stock_list_and_patch():
    h, bid, iid = _setup()
    base = f"/v1/businesses/{bid}/stock"

    lst = client.get(f"{base}/list", headers=h)
    assert lst.status_code == 200, lst.text
    body = lst.json()
    assert body["total"] >= 1
    assert any(x["id"] == iid for x in body["items"])

    patch = client.patch(
        f"{base}/{iid}",
        headers=h,
        json={"new_qty": 45, "adjustment_type": "verification", "reason": "Count"},
    )
    assert patch.status_code == 200, patch.text
    assert float(patch.json()["current_stock"]) == 45.0

    audit = client.get(f"{base}/audit/{iid}", headers=h)
    assert audit.status_code == 200, audit.text
    assert len(audit.json()) >= 1

    code = patch.json().get("item_code")
    if code:
        lookup = client.get(f"{base}/barcode/lookup", headers=h, params={"code": code})
        assert lookup.status_code == 200, lookup.text
