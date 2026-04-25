"""
Production-readiness: automated FLOW 1–3 against the API (same process as manual staging runs).

- Create item + purchase, compare /reports/trade-summary vs /trade-dashboard-snapshot.
- Update purchase, verify aggregates move.
- Delete purchase, verify zeros.
- Cancel purchase, verify excluded from line-based trade reports.
"""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _setup_business_with_item():
    u = uuid.uuid4().hex[:10]
    email = f"pre{u}@test.hexa.local"
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
        json={"name": "PreCat"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    s = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "PreSup", "phone": "9000000001", "gst_number": "32AAAAA0000A1Z1"},
    )
    assert s.status_code == 201, s.text
    sid = s.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "PreItem",
            "type_id": tid,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    return h, bid, iid, sid


def _read_json_sum(h: dict, bid: str, d0: date, d1: date) -> tuple[dict, dict]:
    q = f"from={d0.isoformat()}&to={d1.isoformat()}"
    ts = client.get(
        f"/v1/businesses/{bid}/reports/trade-summary?{q}",
        headers=h,
    )
    assert ts.status_code == 200, ts.text
    sn = client.get(
        f"/v1/businesses/{bid}/reports/trade-dashboard-snapshot?{q}",
        headers=h,
    )
    assert sn.status_code == 200, sn.text
    tj = ts.json()
    sj = sn.json()["summary"]
    return tj, sj


def test_flow_purchase_update_delete_and_summary_matches_snapshot():
    h, bid, iid, sid = _setup_business_with_item()
    d0 = date.today() - timedelta(days=1)
    d1 = date.today() + timedelta(days=1)
    line = {
        "catalog_item_id": str(iid),
        "item_name": "PreItem",
        "qty": 5,
        "unit": "bag",
        "landing_cost": 100.0,
        "kg_per_unit": 50,
        "landing_cost_per_kg": 2.0,
        "tax_percent": 0,
    }
    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [line],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text
    pid = pr.json()["id"]

    tj, sj = _read_json_sum(h, bid, d0, d1)
    assert tj["deals"] == sj["deals"]
    assert abs(float(tj["total_purchase"]) - float(sj["total_purchase"])) < 0.01
    assert abs(float(tj["total_qty"]) - float(sj["total_qty"])) < 0.01
    # Same date window: line spend per supplier sums to global (single supplier in this test).
    q2 = f"from={d0.isoformat()}&to={d1.isoformat()}"
    supr = client.get(
        f"/v1/businesses/{bid}/reports/trade-suppliers?{q2}",
        headers=h,
    )
    assert supr.status_code == 200, supr.text
    sups = supr.json()
    sup_sum = sum(float(s.get("total_purchase") or 0) for s in sups)
    assert abs(sup_sum - float(tj["total_purchase"])) < 0.01
    items = client.get(
        f"/v1/businesses/{bid}/reports/trade-items?{q2}",
        headers=h,
    )
    assert items.status_code == 200, items.text
    item_rows = items.json()
    item_sum = sum(float(r.get("total_purchase") or 0) for r in item_rows)
    assert abs(item_sum - float(tj["total_purchase"])) < 0.01

    g = client.get(
        f"/v1/businesses/{bid}/trade-purchases/{pid}",
        headers=h,
    )
    assert g.status_code == 200, g.text
    row = g.json()
    line = row["lines"][0]
    line["qty"] = 10
    put = {
        "purchase_date": row["purchase_date"],
        "supplier_id": row["supplier_id"],
        "lines": [
            {
                "catalog_item_id": line.get("catalog_item_id"),
                "item_name": line.get("item_name", "PreItem"),
                "qty": 10.0,
                "unit": line.get("unit", "bag"),
                "landing_cost": float(line.get("landing_cost", 100)),
                "kg_per_unit": line.get("kg_per_unit"),
                "landing_cost_per_kg": line.get("landing_cost_per_kg"),
                "tax_percent": line.get("tax_percent"),
            }
        ],
    }
    ur = client.put(
        f"/v1/businesses/{bid}/trade-purchases/{pid}",
        headers=h,
        json=put,
    )
    assert ur.status_code == 200, ur.text
    tj2, sj2 = _read_json_sum(h, bid, d0, d1)
    assert tj2["deals"] == 1
    assert abs(float(tj2["total_purchase"]) - 2.0 * float(tj["total_purchase"])) < 0.02

    dr = client.delete(
        f"/v1/businesses/{bid}/trade-purchases/{pid}",
        headers=h,
    )
    assert dr.status_code == 204, dr.text
    tj3, sj3 = _read_json_sum(h, bid, d0, d1)
    assert tj3["deals"] == 0
    assert float(tj3["total_purchase"]) < 0.01
    assert float(sj3["total_purchase"]) < 0.01


def test_cancelled_purchase_excluded_from_line_reports():
    h, bid, iid, sid = _setup_business_with_item()
    d0 = date.today() - timedelta(days=1)
    d1 = date.today() + timedelta(days=1)
    line = {
        "catalog_item_id": str(iid),
        "item_name": "PreItem",
        "qty": 2,
        "unit": "kg",
        "landing_cost": 50.0,
        "tax_percent": 0,
    }
    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [line],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text
    pid = pr.json()["id"]
    tj, _ = _read_json_sum(h, bid, d0, d1)
    assert tj["deals"] == 1

    cr = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/cancel",
        headers=h,
    )
    assert cr.status_code == 200, cr.text
    tj2, _ = _read_json_sum(h, bid, d0, d1)
    assert tj2["deals"] == 0
    assert float(tj2["total_purchase"]) < 0.01
