"""Supplier create/update/list: extended fields aligned with mobile wizard + HexaApi."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"e{u}@test.hexa.local"
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
    return h, bid


def test_supplier_create_full_payload_and_list_get():
    h, bid = _register_and_business()
    b1 = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": "Broker A", "commission_type": "percent", "commission_value": 2.0},
    )
    assert b1.status_code == 201, b1.text
    broker_a = b1.json()["id"]
    b2 = client.post(
        f"/v1/businesses/{bid}/brokers",
        headers=h,
        json={"name": "Broker B", "commission_type": "percent", "commission_value": 1.5},
    )
    assert b2.status_code == 201, b2.text
    broker_b = b2.json()["id"]

    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Test Cat"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    typ = client.post(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
        json={"name": "Test Type"},
    )
    assert typ.status_code == 201, typ.text
    tid = typ.json()["id"]
    def_sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Item default sup", "phone": "9000000099", "gst_number": "22AAAAA0000A1Z5"},
    )
    assert def_sup.status_code == 201, def_sup.text
    def_sid = def_sup.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Test Item",
            "type_id": tid,
            "default_unit": "kg",
            "hsn_code": "12345678",
            "default_supplier_ids": [def_sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    body = {
        "name": "Wizard Supplier Full",
        "phone": "9876543210",
        "whatsapp_number": "9876543210",
        "location": "Indore",
        "broker_ids": [broker_a, broker_b],
        "gst_number": "22AAAAA0000A1Z5",
        "address": "Warehouse Rd",
        "notes": "Pay on Friday",
        "default_payment_days": 14,
        "default_discount": 1.5,
        "default_delivered_rate": 120.5,
        "default_billty_rate": 30.0,
        "freight_type": "separate",
        "ai_memory_enabled": True,
        "preferences": {
            "category_ids": [cid],
            "type_ids": [tid],
            "item_ids": [iid],
        },
    }
    sr = client.post(f"/v1/businesses/{bid}/suppliers", headers=h, json=body)
    assert sr.status_code == 201, sr.text
    data = sr.json()
    assert data["name"] == "Wizard Supplier Full"
    assert data["phone"] == "9876543210"
    assert data["whatsapp_number"] == "9876543210"
    assert data["location"] == "Indore"
    assert data["gst_number"] == "22AAAAA0000A1Z5"
    assert data["address"] == "Warehouse Rd"
    assert data["notes"] == "Pay on Friday"
    assert data["default_payment_days"] == 14
    assert float(data["default_discount"]) == 1.5
    assert float(data["default_delivered_rate"]) == 120.5
    assert float(data["default_billty_rate"]) == 30.0
    assert data["freight_type"] == "separate"
    assert data["ai_memory_enabled"] is True
    assert data["broker_id"] in (broker_a, broker_b)
    prefs = data.get("preferences_json")
    assert prefs and "category_ids" in prefs and cid in prefs

    sid = data["id"]
    gr = client.get(f"/v1/businesses/{bid}/suppliers/{sid}", headers=h)
    assert gr.status_code == 200, gr.text
    g = gr.json()
    assert g["id"] == sid
    assert g["freight_type"] == "separate"

    lr = client.get(f"/v1/businesses/{bid}/suppliers", headers=h)
    assert lr.status_code == 200, lr.text
    ids = {row["id"] for row in lr.json()}
    assert sid in ids


def test_supplier_patch_preferences_json():
    h, bid = _register_and_business()
    sr = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Patch Me", "phone": "9123456789"},
    )
    assert sr.status_code == 201, sr.text
    sid = sr.json()["id"]
    pr = client.patch(
        f"/v1/businesses/{bid}/suppliers/{sid}",
        headers=h,
        json={
            "preferences": {"category_ids": [], "type_ids": [], "item_ids": []},
            "freight_type": "included",
            "ai_memory_enabled": False,
        },
    )
    assert pr.status_code == 200, pr.text
    out = pr.json()
    assert out["freight_type"] == "included"
    assert out["ai_memory_enabled"] is False
    assert out.get("preferences_json") is not None


def test_supplier_create_invalid_freight_400():
    h, bid = _register_and_business()
    sr = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Bad Freight", "phone": "9000000000", "freight_type": "nope"},
    )
    assert sr.status_code == 400


def test_supplier_create_unknown_broker_400():
    h, bid = _register_and_business()
    bad = str(uuid.uuid4())
    sr = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "No Broker", "phone": "9000000001", "broker_ids": [bad]},
    )
    assert sr.status_code == 400
