"""Catalog insights + line history (by catalog_item_id)."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _setup_cat_and_item():
    u = uuid.uuid4().hex[:10]
    email = f"ci{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "Grains"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "CI sup", "phone": "9000000000", "gst_number": "22AAAAA0000A1Z5"},
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "name": "Basmati",
            "default_unit": "kg",
            "hsn_code": "10063090",
            "default_supplier_ids": [sid],
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    iid = r.json()["id"]
    return h, bid, cid, iid, sid


def _preview_confirm_with_catalog(h, bid, item_id: str, day: str, landing: float, selling: float):
    line = {
        "catalog_item_id": item_id,
        "item_name": "Basmati",
        "qty": 10,
        "unit": "kg",
        "buy_price": landing - 1,
        "landing_cost": landing,
        "selling_price": selling,
    }
    pr = client.post(
        f"/v1/businesses/{bid}/entries",
        json={"entry_date": day, "confirm": False, "lines": [line]},
        headers=h,
    )
    assert pr.status_code == 200, pr.text
    pt = pr.json()["preview_token"]
    cr = client.post(
        f"/v1/businesses/{bid}/entries",
        json={
            "entry_date": day,
            "confirm": True,
            "preview_token": pt,
            "lines": [line],
        },
        headers=h,
    )
    assert cr.status_code == 201, cr.text
    return cr.json()["id"]


def test_catalog_item_insights_and_lines_and_category_insights():
    h, bid, cid, iid, _sid = _setup_cat_and_item()
    d1 = "2026-03-01"
    d2 = "2026-03-15"
    _preview_confirm_with_catalog(h, bid, iid, d1, 100.0, 120.0)
    _preview_confirm_with_catalog(h, bid, iid, d2, 110.0, 125.0)

    q = "from=2026-03-01&to=2026-03-31"
    ir = client.get(
        f"/v1/businesses/{bid}/catalog-items/{iid}/insights?{q}",
        headers=h,
    )
    assert ir.status_code == 200, ir.text
    ins = ir.json()
    assert ins["line_count"] == 2
    assert ins["entry_count"] == 2
    assert ins["total_profit"] != 0
    assert ins["last_entry_date"] == d2
    assert ins["avg_landing"] is not None

    lr = client.get(
        f"/v1/businesses/{bid}/catalog-items/{iid}/lines?{q}&limit=10&offset=0",
        headers=h,
    )
    assert lr.status_code == 200, lr.text
    lines = lr.json()
    assert len(lines) == 2
    assert lines[0]["entry_date"] >= lines[1]["entry_date"]

    cr = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/insights?{q}",
        headers=h,
    )
    assert cr.status_code == 200, cr.text
    cat = cr.json()
    assert cat["item_count"] == 1
    assert cat["linked_line_count"] == 2
    assert cat["top_item_name"] == "Basmati"


def test_duplicate_item_returns_existing_id():
    h, bid, _, iid, sid = _setup_cat_and_item()
    r = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    cat_id = r.json()[0]["category_id"]
    r2 = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cat_id,
            "name": "Basmati",
            "default_unit": "kg",
            "hsn_code": "10063090",
            "default_supplier_ids": [sid],
        },
        headers=h,
    )
    assert r2.status_code == 409, r2.text
    body = r2.json()
    assert "existing_item_id" in body.get("detail", {}) or "existing_item_id" in body
    # FastAPI may wrap detail
    det = body.get("detail")
    if isinstance(det, dict):
        assert det["existing_item_id"] == iid
    else:
        assert body["existing_item_id"] == iid


def test_catalog_item_trade_supplier_prices_from_trade_purchases():
    u = uuid.uuid4().hex[:10]
    email = f"ts{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "GrainsX"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    s1 = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup A", "phone": "9000000001", "gst_number": "32AAAAA0000A1Z1"},
    )
    assert s1.status_code == 201, s1.text
    sid1 = s1.json()["id"]
    s2 = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup B", "phone": "9000000002", "gst_number": "32BBBBB0000B1Z5"},
    )
    assert s2.status_code == 201, s2.text
    sid2 = s2.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "PriceTest Rice",
            "type_id": tid,
            "default_unit": "kg",
            "hsn_code": "10063090",
            "default_supplier_ids": [sid1],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    d1 = date.today() - timedelta(days=2)
    d2 = date.today() - timedelta(days=1)
    b1 = {
        "purchase_date": d1.isoformat(),
        "supplier_id": sid1,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "PriceTest Rice",
                "qty": 1,
                "unit": "kg",
                "landing_cost": 100.0,
                "tax_percent": 0,
            }
        ],
    }
    b2 = {
        "purchase_date": d2.isoformat(),
        "supplier_id": sid2,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "PriceTest Rice",
                "qty": 1,
                "unit": "kg",
                "landing_cost": 80.0,
                "tax_percent": 0,
            }
        ],
    }
    c1 = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=b1)
    assert c1.status_code == 201, c1.text
    c2 = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=b2)
    assert c2.status_code == 201, c2.text

    tr = client.get(
        f"/v1/businesses/{bid}/catalog-items/{iid}/trade-supplier-prices",
        headers=h,
    )
    assert tr.status_code == 200, tr.text
    data = tr.json()
    assert data["catalog_item_id"] == iid
    assert len(data["suppliers"]) == 2
    best = [s for s in data["suppliers"] if s["is_best"]]
    assert len(best) == 1
    assert best[0]["landing_cost"] == 80.0
    assert best[0]["supplier_id"] == sid2
    assert len(data["last_five_landing_prices"]) == 2
    # Most recent first: d2=80, d1=100
    assert data["last_five_landing_prices"][0] == 80.0
    assert data["last_five_landing_prices"][1] == 100.0
    assert abs(data["avg_landing_from_trade"] - 90.0) < 0.01

    q_lines = (
        f"from={(date.today() - timedelta(days=7)).isoformat()}"
        f"&to={date.today().isoformat()}&limit=20&offset=0"
    )
    lr = client.get(
        f"/v1/businesses/{bid}/catalog-items/{iid}/lines?{q_lines}",
        headers=h,
    )
    assert lr.status_code == 200, lr.text
    lines = lr.json()
    assert len(lines) >= 2
    names = {row["supplier_name"] for row in lines if row.get("supplier_name")}
    assert "Sup A" in names and "Sup B" in names
    assert any(row.get("purchase_human_id") for row in lines)
