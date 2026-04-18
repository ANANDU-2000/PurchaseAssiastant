"""Trade purchase lifecycle: due_date, partial payment, overdue derivation."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"tp{u}@test.hexa.local"
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


def _line_body():
    return {
        "item_name": "Rice",
        "qty": 10,
        "unit": "BAG",
        "landing_cost": 100,
        "tax_percent": 0,
    }


def test_create_sets_due_date_from_payment_days():
    h, bid = _register_and_business()
    pd = date.today()
    body = {
        "purchase_date": pd.isoformat(),
        "payment_days": 14,
        "lines": [_line_body()],
    }
    r = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["due_date"] == (pd + timedelta(days=14)).isoformat()
    assert data["paid_amount"] == 0
    assert data["derived_status"] in ("confirmed", "draft", "saved")


def test_partial_payment_derived_partially_paid():
    h, bid = _register_and_business()
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 30,
        "lines": [_line_body()],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    total = float(cr.json()["total_amount"])
    mid = total / 2
    pr = client.patch(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/payment",
        headers=h,
        json={"paid_amount": mid},
    )
    assert pr.status_code == 200, pr.text
    d = pr.json()
    assert d["derived_status"] == "partially_paid"
    assert abs(float(d["remaining"]) - (total - mid)) < 0.01


def test_past_due_date_overdue_when_unpaid():
    h, bid = _register_and_business()
    old = date.today() - timedelta(days=100)
    body = {
        "purchase_date": old.isoformat(),
        "payment_days": 7,
        "lines": [_line_body()],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    d = cr.json()
    assert d["derived_status"] == "overdue"
    assert d["due_date"] == (old + timedelta(days=7)).isoformat()


def test_mark_paid_full():
    h, bid = _register_and_business()
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 5,
        "lines": [_line_body()],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    pid = cr.json()["id"]
    mr = client.post(f"/v1/businesses/{bid}/trade-purchases/{pid}/mark-paid", headers=h, json={})
    assert mr.status_code == 200, mr.text
    assert mr.json()["derived_status"] == "paid"


def test_cancel_purchase():
    h, bid = _register_and_business()
    body = {"purchase_date": date.today().isoformat(), "lines": [_line_body()]}
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    pid = cr.json()["id"]
    xr = client.post(f"/v1/businesses/{bid}/trade-purchases/{pid}/cancel", headers=h)
    assert xr.status_code == 200, xr.text
    assert xr.json()["derived_status"] == "cancelled"


def test_purchase_response_includes_supplier_profile_and_line_hsn():
    h, bid = _register_and_business()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Test grains"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={"category_id": cid, "name": "Test rice", "type_id": tid},
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    up = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{iid}",
        headers=h,
        json={"hsn_code": "10063090"},
    )
    assert up.status_code == 200, up.text

    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={
            "name": "Kerala Supplier",
            "gst_number": "32BBBBB0000B1Z5",
            "address": "Market Road, Thrissur",
            "phone": "9876501234",
        },
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]

    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "Test rice",
                "qty": 5,
                "unit": "BAG",
                "landing_cost": 2000,
                "tax_percent": 0,
            }
        ],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    data = cr.json()
    assert data.get("supplier_gst") == "32BBBBB0000B1Z5"
    assert data.get("supplier_address") == "Market Road, Thrissur"
    assert data.get("supplier_phone") == "9876501234"
    lines = data.get("lines") or []
    assert len(lines) == 1
    assert lines[0].get("hsn_code") == "10063090"
