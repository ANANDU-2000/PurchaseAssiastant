"""Staff role must not receive purchase rates or catalog price snapshots."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"own{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _staff_headers(owner_h, bid):
    suffix = uuid.uuid4().hex[:8]
    phone_digits = "".join(c for c in suffix if c.isdigit())
    if len(phone_digits) < 8:
        phone_digits = f"{int(suffix[:8], 16) % 100000000:08d}"
    phone = f"98{phone_digits[:8]}"
    staff_email = f"staff{suffix}@test.hexa.local"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=owner_h,
        json={
            "full_name": "Staff Redact",
            "phone": phone,
            "email": staff_email,
            "role": "staff",
        },
    )
    assert cr.status_code == 201, cr.text
    pw = cr.json()["generated_password"]
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pw},
    )
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _catalog_item_id(h, bid):
    sid = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup {uuid.uuid4().hex[:6]}", "phone": "9876501234"},
    ).json()["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    cid = cat.json()["id"]
    tid = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    ).json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "SUGAR 50KG",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"], sid


def test_staff_trade_purchase_list_omits_financial_fields():
    owner_h, bid = _owner_and_business()
    item_id, sid = _catalog_item_id(owner_h, bid)
    pr = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=owner_h,
        json={
            "supplier_id": sid,
            "purchase_date": "2026-05-15",
            "lines": [
                {
                    "catalog_item_id": item_id,
                    "item_name": "SUGAR 50KG",
                    "qty": "10",
                    "unit": "bag",
                    "landing_cost": "2750",
                    "kg_per_unit": "50",
                    "landing_cost_per_kg": "55",
                }
            ],
        },
    )
    assert pr.status_code == 201, pr.text

    owner_list = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=owner_h,
    )
    assert owner_list.status_code == 200, owner_list.text
    owner_body = owner_list.json()
    assert owner_body, owner_body
    assert "total_amount" in owner_body[0]
    assert owner_body[0]["lines"][0].get("landing_cost") is not None

    staff_h = _staff_headers(owner_h, bid)
    staff_list = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=staff_h,
    )
    assert staff_list.status_code == 200, staff_list.text
    staff_body = staff_list.json()
    assert staff_body, staff_body
    row = staff_body[0]
    assert "total_amount" not in row
    line = row["lines"][0]
    assert "landing_cost" not in line
    assert "purchase_rate" not in line


def test_staff_unified_search_omits_catalog_prices():
    owner_h, bid = _owner_and_business()
    item_id, sid = _catalog_item_id(owner_h, bid)
    client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=owner_h,
        json={
            "supplier_id": sid,
            "purchase_date": "2026-05-15",
            "lines": [
                {
                    "catalog_item_id": item_id,
                    "item_name": "SUGAR 50KG",
                    "qty": "5",
                    "unit": "bag",
                    "landing_cost": "2750",
                    "kg_per_unit": "50",
                    "landing_cost_per_kg": "55",
                }
            ],
        },
    )
    staff_h = _staff_headers(owner_h, bid)
    sr = client.get(
        f"/v1/businesses/{bid}/search",
        headers=staff_h,
        params={"q": "sugar"},
    )
    assert sr.status_code == 200, sr.text
    body = sr.json()
    items = body.get("catalog_items") or []
    assert items, "expected catalog hit for sugar"
    hit = items[0]
    assert "last_purchase_price" not in hit
    assert "last_selling_rate" not in hit
    assert "default_landing_cost" not in hit
