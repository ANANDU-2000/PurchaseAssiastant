"""Catalog insights + line history (by catalog_item_id)."""

import uuid

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
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={"category_id": cid, "name": "Basmati", "default_unit": "kg"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    iid = r.json()["id"]
    return h, bid, cid, iid


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
    h, bid, cid, iid = _setup_cat_and_item()
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
    h, bid, _, iid = _setup_cat_and_item()
    r = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    cat_id = r.json()[0]["category_id"]
    r2 = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={"category_id": cat_id, "name": "Basmati", "default_unit": "kg"},
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
